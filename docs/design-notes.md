# Design notes

The significant design decisions in v1, each with the reason for it and the
alternative that wasn't taken.

## Data and context

### Two NHS England datasets, last 24 months

The agent works on RTT incomplete pathways and A&E attendances and 4-hour performance, at provider level, for the 24 most recent monthly files: RTT Sep 2024 to Aug 2026, A&E Oct 2024 to Sep 2026. Both are official statistics with stable formats, and they have well-documented traps (total rows, mergers, missing submissions) that make wrong answers easy and therefore worth testing. *Not taken:* a wider set of datasets. That would have spread the effort across ingestion before there was any way to measure accuracy.

### Clean tidy parquet, built by logged ingest scripts

`data/ingest/` downloads the raw files and writes one tidy parquet per dataset. Every cleaning step prints its row counts before and after, and no row is ever dropped silently. The agent then queries a small, consistent table instead of messy spreadsheets, and every cleaning decision can be audited. *Not taken:* letting the agent read the raw CSV and ZIP files directly. That would make every answer depend on the model re-solving the cleaning each time.

### A data catalogue as the agent's context

`data/catalogue.yaml` describes every table and column: type, meaning, units, examples, and the gotchas from `data/notes.md`. All of it goes into the system prompt, where it is prompt-cached across questions. The traps that cause wrong answers are about meaning, not schema, so the model needs them written down next to the columns they affect. *Not taken:* giving only column names and types, or retrieving parts of the catalogue per question. The catalogue is small enough (about 8,700 tokens) to send whole, and caching makes that cheap.

## Evaluation

### Build the eval before the agent

The 20 v1 questions, their ground truth and the grader existed before the first line of agent code. Without a fixed set of questions with known answers, every later change would have been judged by eye. *Not taken:* building the agent first and testing it on ad hoc questions. That gives no way to tell whether a change helped.

### Questions with exactly one answer, ground truth computed in code

Each question pins down the month, the measure and the set of providers, and `eval/ground_truth/compute_answers.R` computes every expected answer from the clean data into a readable `answers.json`. The script stops on ranking ties or ambiguous thresholds. That makes grading automatic and objective (numbers within 1%, everything else exact), and the key can be rebuilt after a data refresh, with changes visible in the diff. *Not taken:* open questions graded by a person or an LLM judge. That's more realistic, but noisier and more expensive, so it's better added later as a second layer.

### Trap questions built from the gotchas

About a third of the questions are traps: falling for a known gotcha (summing C_999 with the specialty rows, averaging percentages, adding cumulative wait bands) gives a different number, so the score shows whether the agent applies the catalogue. *Not taken:* a set of only straightforward lookups. Those would mostly test arithmetic.

### Removing answer leaks from the catalogue

The first catalogue quoted exact figures in its gotchas: the national total, the 4-hour and 18-week percentages, and provider counts. Some of these were eval answers, or gave them away. They were replaced with descriptions ("about 31k higher than published"), and both the catalogue and the prompt are scanned for every expected answer. The agent never copied the values, but an eval whose answers are in the prompt can't distinguish computing from copying. *Not taken:* leaving the figures in because they made the gotchas concrete.

### Not telling the agent which questions it should refuse

Questions the data can't answer (q23–q25) have answer type `refusal`. The agent is given only `asks_for` and `asks_for_units`, which describe what the question asks for, such as a number of patients. A first version passed the question's `units`, which described the expected refusal and so told the agent to refuse. A test now checks that no refusal prompt mentions refusing. *Not taken:* labelling these questions as refusals in the prompt. That would test instruction-following, not the agent's judgement.

## Agent

### Structured output, validated with pydantic

The model replies with JSON in a fixed schema (plan, datasets, R code, answer type, refusal reason), enforced with the API's JSON-schema output format and validated again with pydantic. This removes parsing failures and gives every reply the same fields to log and analyse. *Not taken:* parsing R code out of free-form text, or using a tool call. Free-form text breaks often, and a single forced schema is simpler than a tool loop for one step.

### The answer comes from running R, not from the JSON

The model writes R that assigns `answer`. The runner executes it, exports `answer` as JSON and checks its type. The model can't know the number before the code runs, and taking the value from the run means the reported answer is exactly what the code computed. *Not taken:* a second model call to read the output and state the answer. That doubles the cost and adds a place for transcription errors.

### One retry with the error sent back

If the JSON is invalid, the R code fails, or `answer` has the wrong format, the problem is sent back once. Most such failures are fixable with the error message, and capping retries at one keeps the cost per question bounded and makes "right first time" a meaningful measure. *Not taken:* unlimited retries, which hide fragility and make cost unpredictable.

## Execution and cost

### A locked-down Docker sandbox

Model-written R runs in a fresh container each time:
- no network,
- `data/clean` mounted read-only,
- a read-only root filesystem,
- a 30-second limit (enforced inside the container, with a backstop from outside),
- 1 GB of memory and no swap,
- a non-root user with no Linux capabilities, and a process cap.

All of these were checked by hand: blocked DNS and direct IP connections, a refused write, a timeout at 30 s, and an out-of-memory kill. Running untrusted code on the host is unsafe, and the limits also stop slow or memory-hungry code from hanging a run. *Not taken:* running `Rscript` on the host, or using R's own sandboxing packages, neither of which isolates the filesystem and network.

### A spend cap per run, checked before every call

Before each call the worst-case cost is computed and checked against `BUDGET_USD` (default $5 per process), using the published per-token prices stored with the date they were checked. The worst case counts input exactly (via token counting) at the cache-write rate, plus the full `max_tokens` of output. A call that could go over is refused, and every call's actual cost is appended to a ledger. *Not taken:* relying only on the account-level spend limit in the Console. That stops spending but can't stop one runaway loop or tell you which run spent the money.

## Development process

### Fixes applied and measured in stages

Changes were applied one stage at a time: baseline, then the harness fixes, then the refusal option. Each stage got 3 labelled runs on all 30 questions, compared with bootstrap intervals in `eval/analysis/compare_runs.R`. Measuring each change separately shows which one moved which measure. *Not taken:* applying every fix at once. That would show only the combined effect.

### Harness fixes: drop the answer-type label check, preload packages

The first failure analysis found that every retry came from the harness, not from the analysis. There were two causes:
- **The answer-type label:** replies were rejected when their declared answer type differed from the question's, even though `coerce_answer()` already checks the actual value.
- **Missing packages:** code used `%>%` without loading dplyr.

The label check was removed, and dplyr, tidyr and arrow are now loaded before every script. *Not taken:* prompt-only fixes, such as asking the model to always load dplyr, which reduce the problem but don't remove it.

### A refusal option in the reply schema

The reply can set `refusal_reason` instead of giving R code, and one prompt line says to refuse only when the data genuinely can't answer. Before this, the agent could only express "can't answer" by setting `answer` to NA, which failed. *Not taken:* a separate answerability step before answering, which adds a call per question. Also not taken: a prompt-only refusal in free text, which the grader couldn't separate reliably from an answer. False refusals are tracked as their own measure, and there were none.

### A pre-run guard for isTRUE()/isFALSE() inside filter()

`filter(isFALSE(col))` runs without error but tests the whole column at once, so the filter keeps all rows or none and the answer is silently wrong. A retry can't catch it, because nothing fails. A static check now finds these calls before running (it matches parentheses and ignores strings and comments) and sends the code back. Replayed over all 411 earlier code attempts, it flags exactly the one buggy attempt and nothing else. *Not taken:* sanity checks on results, such as rejecting zero answers, which would also reject correct zeros and miss non-zero wrong answers.

## Models

### Claude Haiku 5.5 for development, Claude Sonnet 5.5 for final runs

All results so far are on Haiku 5.5, at about $0.0005 per question, which made repeated runs affordable under the $5 cap. The model is configurable, and Sonnet 5.5 runs with the server-side refusal fallback enabled. *Not taken:* developing on the largest model, which would have used the budget in a few runs and left no room for repeated measurement.

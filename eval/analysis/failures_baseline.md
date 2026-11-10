# Baseline agent: first live evaluation (draft)

**Status:** draft for review
**Date:** 2026-11-10
**Agent:** baseline (`agent/core.py` at `b89191b`), one retry allowed
**Model:** `claude-haiku-5-5`
**Eval set:** v1, 20 questions (`eval/questions.yaml`), data as of 2026-10-21
**Runs:** `eval/runs/20261110T152618Z`, `20261110T152750Z`, `20261110T152920Z` (local, gitignored)

## Results

| | Run 1 | Run 2 | Run 3 | Average |
|---|---|---|---|---|
| Accuracy | 20/20 (100%) | 20/20 (100%) | 20/20 (100%) | **100%** |
| Right first time | 19/20 | 17/20 | 19/20 | 18.3/20 (92%) |
| Retries used | 1 | 3 | 1 | 1.7 |
| Model calls | 21 | 23 | 21 | 21.7 |
| Output tokens | 12,856 | 13,636 | 12,673 | 13,055 |
| Total cost | $0.0096 | $0.0092 | $0.0085 | **$0.0091** |
| Cost per question | $0.00048 | $0.00046 | $0.00042 | **$0.00046** |

- Total spend across the three runs: **$0.0273**. This matches `.spend/ledger.json` (65 calls).
- No run came near the $2 per-run cap (`BUDGET_USD` in `.env`). The most expensive single call cost $0.0012, against a worst-case estimate of $0.0052.
- Input token counts in `run.json` exclude cached tokens. The ~8,700-token system prompt (instructions plus catalogue) was written to the cache once, in run 1. After that, every call read it from the cache at $0.01 per million tokens. Most of the cost is output tokens.

## Failure analysis

**No question was answered wrongly in any run (0 of 60).** There are no final failures to categorise.

The closest thing to failures is the **5 first attempts that failed and were fixed by the one allowed retry**. They are analysed below, because they cost an extra call each and show where the agent is fragile.

### Summary

| Category | Count | Question ids (run) | Consistent? |
|---|---|---|---|
| Wrong answer format: declared `answer_type` "count" instead of "number"; the computed value was correct | 3 | q10 (runs 1, 3), q11 (run 2) | q10 in 2 of 3 runs, q11 in 1 of 3 |
| Other: R error, recovered on retry (used `%>%` without loading dplyr) | 2 | q04 (run 2), q15 (run 2) | 1 of 3 runs each |
| Wrong dataset or column | 0 | | |
| Misread units or definitions | 0 | | |
| Ignored a notes.md gotcha | 0 | | |
| R error not recovered | 0 | | |
| Wrong statistical method | 0 | | |

No first-attempt failure happened in all 3 runs. The most repeatable is q10's answer-type label, seen in 2 of 3 runs.

### 1. Declared answer type "count" instead of "number" (3 cases)

**What happened:** q10 and q11 ask for a number of pathways or attendances, and the eval types both as `number`. The model's JSON said `"answer_type": "count"`. The agent rejects a reply whose declared type doesn't match the question's, so it sent the reply back. **The R code was already correct, and the retry resubmitted identical code with the label changed.**

**Evidence:** q10, run 1. Expected answer type: `number` (pathways).

```r
answer <- rtt %>%
  filter(period == as.Date("2026-08-01"), is_all_specialties_total == TRUE) %>%
  summarise(v = sum(over_52_weeks, na.rm = TRUE) - sum(over_65_weeks, na.rm = TRUE)) %>%
  pull(v) %>%
  as.numeric()
```

Feedback sent: `The question needs answer_type "number", but your reply says "count".`

Run 3's q10 and run 2's q11 follow the same pattern. Run 2's q11 computed Sep 2026 minus Oct 2024 attendances correctly on the first attempt.

**Why:** "How many pathways…" reads naturally as a count, and the value is a whole number. This is the harness being stricter than it needs to be, not an error in the analysis. `coerce_answer()` already checks the actual value against the expected type, so the declared label adds nothing.

### 2. Used `%>%` without loading dplyr (2 cases)

**What happened:** in run 2, q04 and q15 used the `%>%` pipe while calling dplyr functions as `dplyr::filter(...)`, without `library(dplyr)`. `%>%` only exists once dplyr (or magrittr) is attached, so R stopped before computing anything. The retry added `library(dplyr)`, and both answers were then correct.

**Evidence:** q04, run 2. Expected answer type: `count` (providers).

```r
ae <- arrow::read_parquet("data/clean/ae_provider.parquet")
sep <- ae %>% dplyr::filter(period == as.Date("2026-09-01"), has_ae_activity == FALSE)
answer <- as.integer(dplyr::n_distinct(sep$org_code))
```

```
Error in ae %>% dplyr::filter(...) : could not find function "%>%"
Execution halted
```

q15 in run 2 was the same: `%>%` with no `library(dplyr)`, and the same error.

**Why:** the system prompt lists the available packages but doesn't say they need loading. Run 2 also used `%>%` rather than the native `|>`, which needs no package.

### Gotchas: all handled

Every trap question passed in all three runs. Spot checks of the code show the agent applied the catalogue gotchas, for example:
- **C_999 totals:** it filtered with `is_all_specialties_total` (q07, q12, q20).
- **Cumulative wait bands:** it used `over_52_weeks - over_65_weeks` (q10).
- **Ratio of sums:** it computed percentages from summed counts (q08, q13).
- **Admissions via A&E:** it used `emergency_admissions_via_ae` (q17).
- **Merger:** it compared like for like across the RA7/RVJ merger (q18).
- **Missing submissions:** it restricted the comparison to providers present in both months (q19).

## Caveats on these results

1. **The eval is saturated for this model.** At 100% on every run, v1 can't tell a better agent from a worse one, and fixing the two categories below changes cost and latency, not accuracy. Harder or more open questions are needed before the score can guide changes.
2. **Some answers are visible in the catalogue.** Expected answers or their inputs appear in `data/catalogue.yaml`, which the agent reads. The genuine leaks are q07 (7,189,213), q13 (65.2%), q08 (74.4%), q09 (both 4-hour percentages, 74.4% and 60.6%) and q14 (144 providers). q04's and q06's small counts also appear, though probably by coincidence. q05's 50,582 trolley waits appear only in `data/notes.md`, which the agent doesn't read. **In these runs the agent didn't use the leaked values.** Every one of the 60 answers was computed by code that reads the parquet files, and none of the code contains an expected value or assigns `answer` a literal. But nothing prevents a model from copying them.
3. **Three runs is a small sample.** The retry rate (5 of 60 first attempts) is a rough estimate.

## Proposed fixes (not implemented)

Ranked by expected impact. Accuracy is already 100%, so impact here means fewer wasted retries, lower cost and latency, and less fragility on harder questions.

### 1. Stop rejecting replies over the declared answer type (agent logic): 3 of 5 retries

- **Change:** in `agent/core.py`, drop the check that the declared `answer_type` matches the question's. `coerce_answer()` already validates the value R produced against the expected type, so a mismatch is reported only when the value itself is wrong. Either remove `answer_type` from the reply schema, or keep it as information only.
- **Why first:** it's the largest category and repeats on the same question (q10 in 2 of 3 runs). It costs a model call each time and protects against nothing the value check doesn't already catch. It's a deterministic code change with no prompt risk.
- **Expected effect:** about 60% fewer retries at current rates (roughly 1 per run instead of 1.7), with right-first-time going from 92% to about 97%.

### 2. Load the core packages before the model's code runs (agent logic, plus one prompt line): 2 of 5 retries

- **Change:** in `agent/core.py`, put a fixed prelude in front of every script, mirroring the `ANSWER_EXPORT` footer: `suppressPackageStartupMessages({library(dplyr); library(tidyr); library(arrow)})`. Add one line to the system prompt saying these are already loaded and that `|>` is preferred.
- **Why second:** it's the only category that's a real code error. Loading the packages in the runner removes it entirely, rather than relying on the model to remember. It's cheap, deterministic and helps every future question.
- **Risk:** small. Masking messages are suppressed, and a script that also calls `library(dplyr)` still works.

### Also worth doing (outside the two categories)

- **Remove the leaked values from the catalogue** before the eval is used to compare agents or prompts. Keep the gotcha wording, but replace exact figures with descriptions, e.g. "national totals here are about 31k higher than published".
- **Add harder questions**, so that accuracy can move again.

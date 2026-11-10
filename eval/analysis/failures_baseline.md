# Baseline agent: first live evaluation (draft)

**Status:** draft for review
**Date:** 2026-11-10
**Agent:** baseline (`agent/core.py` at `b89191b`), one retry allowed
**Model:** `claude-haiku-5-5`
**Eval set:** v1, 20 questions (`eval/questions.yaml`), data as of 2026-10-21
**Runs:** `eval/runs/20261110T152618Z`, `20261110T152750Z`, `20261110T152920Z` (local, gitignored)

## Bug fix: isTRUE()/isFALSE() inside filter() (q04)

### The bug

In the v1.1 baseline (run `20261110T155534Z`), q04 returned **0** instead of the correct count. The generated code was:

```r
answer <- sep26 %>% filter(isFALSE(has_ae_activity)) %>% distinct(org_code) %>% nrow()
```

`isFALSE()` (and `isTRUE()`) return a **single** TRUE or FALSE for the whole column, not one value per row. So `filter()` keeps every row or none. The code runs without error, and the answer is silently wrong. The harness fixes and the refusal option don't address it, because nothing fails.

### The fix (`ff345e2`)

- **Pre-run check** in `agent/core.py` (`scalar_tests_in_filter()`). It scans the code for `filter(...)` and `dplyr::filter(...)` calls, matching parentheses and skipping strings and comments. If any call uses `isTRUE()` or `isFALSE()`, the code isn't run. It goes back as a retry, explaining that these return one value for the whole column and to use the column directly, `!column`, or `column == FALSE` instead.
- **One line in the system prompt** saying the same.
- **Tests** (`tests/agent/test_code_checks.py`, 14 cases):
  - **Caught:** `filter(isFALSE(x))`, `dplyr::filter(...)`, multi-line calls and `!isTRUE(x)`.
  - **Allowed:** `filter(!x)`, `filter(x == FALSE)`, `filter(x)`, `isTRUE()` outside `filter()`, the pattern inside a string or comment, and functions merely named like filter.
  - **Agent level:** flagged code is sent back and never run.

### Before and after

| | Runs | q04 wrong | Pattern used | Check fired |
|---|---|---|---|---|
| Before the fix: q04 alone | 10 | 0 | 0 | — |
| After the fix: q04 alone | 10 | 0 | 0 | 0 |
| After the fix: q04 in the 3 full runs | 3 | 0 | 0 | 0 |

**The bug is too rare for 10 runs to measure.** Before the fix, q04 failed 0 times in 10. Across every live run so far, 26 q04 attempts and 420 code attempts in all, the pattern appeared **exactly once** (the baseline failure above). Ten runs either side of the fix can't show a difference at that rate. The evidence that the fix works is instead:

1. **The tests:** the pattern is caught, correct code is allowed, and flagged code is never run.
2. **A replay over every earlier run:** across all 411 code attempts already on disk, the check flags exactly the one buggy attempt and nothing else (no false positives).

### Full eval after the fix (all 30 questions, 3 runs)

Runs `20261110T163126Z`, `20261110T163333Z` and `20261110T163535Z`, label `isfalse-check`.

| Measure | + refusal option (before) | + isFALSE check (after) | Change |
|---|---|---|---|
| Accuracy | 100% | 100% | 0 |
| Right first time | 100% | 100% | 0 |
| Retries per run | 0 | 0 | 0 |
| Refusal accuracy (q23–q25) | 100% | 100% | 0 |
| False refusals | 0 | 0 | 0 |
| Cost per question | $0.00049 | $0.00045 | −$0.00004 |

Nothing else changed. The check didn't fire on any question, so it added no retries or cost.

## Update: v1.1 stage results (all 30 questions)

The eval was extended to 30 questions (q21–q30, v1.1). The agent was then run in three stages on `claude-haiku-5-5`, 3 runs each, on branch `feat/agent-fixes`:

1. **Baseline:** the agent unchanged.
2. **+ harness fixes** (`6c99f9d`): both fixes proposed below. The declared answer-type check was dropped, and dplyr, tidyr and arrow are loaded before every script (with a prompt line preferring `|>`).
3. **+ refusal option** (`633ab9b`): the reply can set `refusal_reason` instead of giving R code, plus one prompt line, "refuse only when the data genuinely can't answer the question".

Produced by `eval/analysis/compare_runs.R`. Outputs are in `docs/results/` (`stage_comparison.csv`, `stage_comparison.png`, `question_results.csv`). Intervals are 95% percentile bootstrap intervals, resampling questions (2,000 resamples).

### All 30 questions

| Measure | Baseline | + harness fixes | + refusal option | Change, baseline → final |
|---|---|---|---|---|
| Accuracy | 88.9% (76.7–98.9) | 90.0% (80.0–100) | **100%** | +11.1 pts |
| Right first time | 86.7% (75.6–96.7) | 88.9% (76.7–98.9) | **100%** | +13.3 pts |
| Retries per run | 2.67 | 2.00 | **0** | −2.67 |
| Cost per question | $0.00055 | $0.00050 | **$0.00049** | −$0.00007 |
| Refusal accuracy (q23–q25) | 0% | 0% | **100%** | +100 pts |
| False refusals | 0 | 0 | **0** | — |

### Split by question set

| Measure | Set | Baseline | + harness fixes | + refusal option |
|---|---|---|---|---|
| Accuracy | q01–q20 | 98.3% (95.0–100) | 100% | 100% |
| | q21–q30 | 70.0% (40.0–100) | 70.0% (40.0–100) | 100% |
| Right first time | q01–q20 | 95.0% (90.0–100) | 98.3% (95.0–100) | 100% |
| | q21–q30 | 70.0% (40.0–100) | 70.0% (40.0–100) | 100% |
| Retries per run | q01–q20 | 0.67 | 0.33 | 0 |
| | q21–q30 | 2.00 | 1.67 | 0 |
| Cost per question | q01–q20 | $0.00045 | $0.00038 | $0.00044 |
| | q21–q30 | $0.00075 | $0.00073 | $0.00059 |

### What changed at each stage

- **Baseline.**
  - **Refusal questions:** q23–q25 failed in every run, since the agent couldn't refuse. Its retries there came from setting `answer` to NA, in effect trying to say "can't answer".
  - **The other new questions:** q21, q22 and q26–q30 passed in every run.
  - **q04 failed once with a real bug:** the code used `filter(isFALSE(has_ae_activity))`, and `isFALSE()` returns a single FALSE for a whole column, so the filter kept no rows. That's a wrong method; neither harness fix addresses it.
- **+ harness fixes.**
  - **Gone:** no answer-type or missing-dplyr retries occurred.
  - **q01–q20:** reached 100%, with one retry left (a variable-name typo in q18, recovered).
  - **q21–q30 retries:** the remaining ones were all on q23 and q25, again the agent trying to express a refusal through NA.
- **+ refusal option.** 90 of 90 answers were correct and right first time, with zero retries.
  - **q23–q25:** refused correctly in every run (9 of 9).
  - **False refusals:** none.
  - **Reasons:** every reason was specific and accurate. For example, for q25: "measures patients waiting more than 12 hours from the decision to admit to admission (trolley waits), not from arrival. The 12-hours-from-arrival figure is in NHS England's separate ECDS supplementary analysis". For q24, the agent also offered the pathway count as an alternative.

### Caveats

- **The eval is saturated again.** At 100% on every run, v1.1 can no longer tell agent versions apart. The next agent change needs harder questions, or a harder model setting, before its effect can be measured.
- **The intervals at 100% have zero width.** When every question scores 100%, every bootstrap resample does too. This is a limit of the method, not evidence of certainty. With 30 questions, an agent that fails 1 question in 30 would often score 100% on a given set.
- **The q21–q30 intervals are wide** (40–100%), because there are only 10 questions. Stage differences inside that set rest on q23–q25 alone.
- **Three runs per stage is a small sample.** The baseline's single q04 failure is the only run-to-run difference in accuracy.

## Update: new baseline after removing catalogue leaks

Leaked answers were removed from `data/catalogue.yaml` in `e00f53e` (see caveat 2 below). The baseline agent was then rerun 3 times on `claude-haiku-5-5`, with no other changes. **This is the new baseline.**

Runs: `20261110T153856Z`, `20261110T154019Z`, `20261110T154144Z`.

| | Run 1 | Run 2 | Run 3 | Average | Before leak removal |
|---|---|---|---|---|---|
| Accuracy | 20/20 | 20/20 | 20/20 | **100%** | 100% |
| Right first time | 20/20 | 20/20 | 19/20 | **19.7/20 (98%)** | 18.3/20 (92%) |
| Retries used | 0 | 0 | 1 | 0.3 | 1.7 |
| Total cost | $0.0094 | $0.0089 | $0.0081 | **$0.0088** | $0.0091 |
| Cost per question | $0.00047 | $0.00045 | $0.00040 | **$0.00044** | $0.00046 |

- **Accuracy didn't change.** The leaked values weren't being used before either: all answers were computed from the data both times.
- **The one retry** was the same `%>%`-without-dplyr error as before (q03, run 3; recovered).
- **The answer-type label mismatch (q10, q11) didn't recur.** That's 0 cases in 3 runs, against 3 cases in 3 runs before. With three runs a side, this could easily be chance, so it doesn't yet show the catalogue edit fixed anything. Fix 1 below still removes the cause.
- **Cost moved by $0.0003 per run,** which is within run-to-run variation.

The questions added in v1.1 (q21–q30) aren't in these runs: they have no ground truth yet.

## Results (first live run, before leak removal)

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

## Proposed fixes (implemented in `6c99f9d`; results in the v1.1 stage update above)

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

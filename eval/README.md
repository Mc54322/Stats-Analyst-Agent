# Evaluation set

30 questions about the NHS RTT and A&E data, each with exactly one correct
answer, for measuring how often the agent gets things right.

```
eval/
├── questions.yaml               # the questions, answer types, grading rules, gotcha tested
├── run_eval.py                  # runs the questions through the agent and grades them
├── ground_truth/
│   ├── compute_answers.R        # computes every expected answer from data/clean
│   └── answers.json             # generated output, committed so changes show in diffs
├── grading/
│   ├── grade.R                  # grade_answer(id, answer): PASS/FAIL against answers.json
│   └── grade_batch.R            # grades a whole run in one call (used by run_eval.py)
├── analysis/                    # write-ups of eval results
└── runs/                        # one folder per run (gitignored)
```

## Questions

[`questions.yaml`](questions.yaml) lists each question with its category
(lookup, trend, comparison, ranking, trap), the dataset(s) it uses, its answer
type and units, the `data/notes.md` gotcha it tests, and a difficulty from 1
to 3.

- **q01–q20 (v1)** are ordered from easiest to hardest. Trap questions are built
  so that falling for a gotcha gives a different answer, e.g. summing C_999
  with the specialty rows, averaging percentages, or adding cumulative wait bands.
- **q21–q30 (v1.1)** are harder:
  - figures built up from provider data (ICB and region totals),
  - an RTT/A&E join,
  - time series where mergers or missing submissions change the answer,
  - three questions the data can't answer (q23–q25).

### Refusal questions

For q23–q25 the correct answer is a refusal that says why the data can't
answer (e.g. the data counts pathways, not patients). Their `answer_type` is
`refusal`. `asks_for` and `asks_for_units` record what the question asks for,
and that's all the agent is told, so it isn't warned in advance that it should
refuse.

## Ground truth

Expected answers come from code, not from hand calculation:

```sh
Rscript eval/ground_truth/compute_answers.R
```

This reads the clean parquet files and writes `answers.json`, recording the
data date and source row counts. The script stops if:
- a ranking has a tie at its cut-off,
- an answer has the wrong shape, or
- a refusal question's proof fails (i.e. the data turns out to contain what
  the question needs).

Any of these would make a question ambiguous. A refusal's expected answer is the
list of keywords its reason must mention.

**Rerun it after refreshing the data and review the diff of `answers.json`.**
NHS England revises past months, so expected answers can change. A changed
answer should be explained, not just committed.

## Grading

Rules are in `questions.yaml`:

| Answer type | PASS when |
|---|---|
| number | within 1% relative error |
| count | exactly equal |
| ranking list | same items in the same order |
| yes/no | exactly equal |
| refusal | the answer is `refusal("why ...")`, the reason is at least 20 characters and mentions one of the question's keywords (any case) |

Refusing a question the data can answer always fails.

```r
source("eval/grading/grade.R")
grade_answer("q07", 7189213)                                             # PASS
grade_answer("q24", refusal("The data counts pathways, not patients."))  # PASS
grade_answer("q24", 6200000)                                             # FAIL: expected a refusal
```

## Running the eval

```sh
uv run python eval/run_eval.py                       # all questions, Claude Haiku 5.5
uv run python eval/run_eval.py --questions q21 q26   # a subset
uv run python eval/run_eval.py --mock                # fake model, no API calls
```

Each run is saved to `eval/runs/<timestamp>/` and goes through the spend cap
(`BUDGET_USD`).

**The baseline agent has no way to refuse yet,** so it can't pass q23–q25. A
`--mock` run scores 27/30 for the same reason.

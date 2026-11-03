# Evaluation set (v1)

20 questions about the NHS RTT and A&E data, each with exactly one correct
answer, for measuring how often the agent gets things right.

```
eval/
├── questions.yaml               # the questions, answer types, grading rules, gotcha tested
├── ground_truth/
│   ├── compute_answers.R        # computes every expected answer from data/clean
│   └── answers.json             # generated output, committed so changes show in diffs
└── grading/
    └── grade.R                  # grade_answer(id, answer): PASS/FAIL against answers.json
```

## Questions

[`questions.yaml`](questions.yaml) lists each question with its category
(lookup, trend, comparison, ranking, trap), the dataset(s) it uses, its answer
type and units, the `data/notes.md` gotcha it tests, and a difficulty from 1
to 3. They are ordered from easiest to hardest. Trap questions are built so that
falling for a gotcha gives a different answer, e.g. summing C_999 with the
specialty rows, averaging percentages, or adding cumulative wait bands.

## Ground truth

Expected answers come from code, not from hand calculation:

```sh
Rscript eval/ground_truth/compute_answers.R
```

This reads the clean parquet files and writes `answers.json`, recording the
data date and source row counts. The script stops if a ranking has a tie at
its cut-off or if any answer has the wrong shape, because either would make a
question ambiguous.

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

```r
source("eval/grading/grade.R")
grade_answer("q07", 7189213)   # PASS q07 +0.00% from expected
grade_answer("q03", "yes")     # FAIL q03
```

The agent harness will call the same rules when it scores a full run.

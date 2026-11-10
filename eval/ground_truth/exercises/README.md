# Ground truth for q21–q30 (exercises)

The expected answers for q21–q30 are written by hand here, then moved into
`../compute_answers.R`. Until then, these questions have no entry in
`answers.json`, and the eval runner skips them.

```
exercises/
├── q21.R … q30.R   fill-in-the-blanks: plan, tools, skeleton, hints
├── check.R         check_answer(id, answer): PASS/FAIL against the hidden key
└── key.rds         hidden answers, stored scrambled (don't open it)
```

## Working through a file

1. Start R in the project folder (`getwd()` should end in `Stats Analyst Agent`).
2. Open `qNN.R` and read the header: the question, the answer format, the
   gotcha, the **Plan** and the **Tools you'll need**.
3. Replace every `.___` (or `.___()` where a whole step goes), dot included,
   with your code. Running a line that still has a blank tells you so.
4. Run the file top to bottom. The last line prints **PASS** or **FAIL**
   (plus how far off you are for numbers; you need to be within 1%).
5. Stuck? The **Hints** at the bottom give one hint per blank.

## Refusal questions (q23, q24, q25)

These ask for something the data can't provide. The correct answer is
`refusal("<why>")`, and each file has you prove it first: R code that shows
the data lacks what's needed, then `stopifnot()` so the file only reaches the
refusal if the proof holds.

A refusal passes only if its reason says **why** the data can't answer, e.g.
what it measures instead or which months it covers. "No data" on its own fails.

## When you get a FAIL

1. Run `answer` on its own. Is it the right shape (one number, a list of codes,
   a refusal)?
2. Run the pipeline step by step and look at each intermediate table.
3. Re-read the gotcha in [`data/notes.md`](../../../data/notes.md).
4. The key could be wrong too. If you're confident in your method, say so.

## After a question passes

Copy the working code into `../compute_answers.R` as the entry for that
question, then rerun `Rscript eval/ground_truth/compute_answers.R`. That puts
the answer in `answers.json`, so the eval runner and grader include it.

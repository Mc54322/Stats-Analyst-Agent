# Writing the ground truth: practice files q01–q20

Each file `q01.R` … `q20.R` answers one question from
[`eval/questions/questions.yaml`](../questions/questions.yaml). You write the R
code; `check_answer()` tells you whether your answer matches the hidden key.

The files get harder as you go. q01–q05 are almost finished and only need a few
small blanks. By q16–q20 you write the whole thing yourself from a plan.
**Do them in order.** Each one introduces at most one or two new tools and
reuses the ones before it.

## 1. Open the project

R has to start in the project folder so it can find the data and the packages.

- **VS Code:** open the `Stats Analyst Agent` folder, open a terminal
  (`` Ctrl+` ``), and type `R`. Check with `getwd()`: it should end in
  `Stats Analyst Agent`.
- **RStudio:** double-click `Stats Analyst Agent.Rproj`.

If you see `there is no package called 'dplyr'`, R didn't start in the project
folder.

## 2. Work through a file

1. Open `eval/truth/q01.R` and read the header: the question, what the answer
   looks like, which gotcha from [`data/notes.md`](../../data/notes.md) applies,
   the **Plan**, and the **Tools you'll need**.
2. Find the blanks. They look like `.___` (dot plus three underscores), or
   `.___()` where a whole step goes. Replace the whole thing, dot included,
   with your code.
3. Run the file **top to bottom**:
   - **VS Code:** put the cursor on the first line and press `Cmd+Enter`
     repeatedly to run one line or step at a time, or select everything and
     press `Cmd+Enter`.
   - **RStudio:** `Cmd+Shift+Enter` runs the whole file.
   - Or, in the R console: `source("eval/truth/q01.R")`.

   If you run a line that still has a blank, R says *"This line still has a
   blank (.___) to fill in"*. That's expected, not a bug.
4. The last line, `check_answer("q01", answer)`, prints **PASS** or **FAIL**.
   For number answers it also prints how far off you are, e.g. `+3.20% from
   the expected value`. You need to be within 1%.

Stuck? Each file has a **Hints** section at the bottom: one hint per blank (or
per plan step in q16–q20). Each hint points the way without giving you the code.

## 3. When you get a FAIL

Work through this list in order:

1. **Look at your answer.** Run `answer` on its own. Is it the right kind of
   thing: one number, a yes/no, or a list of codes? `check_answer` also tells
   you if the shape is wrong (e.g. a table instead of a single value).
2. **Re-read the Plan** and check each step does what it says. Run the
   pipeline one step at a time (delete the later lines temporarily) and look
   at the table after each step. Is it the month, rows and columns you expect?
3. **Check the gotcha** named in the header against
   [`data/notes.md`](../../data/notes.md). Most FAILs on the trap questions
   come from exactly that gotcha, e.g. summing the C_999 rows together with
   the specialty rows, or averaging percentages.
4. **Remember the key could be wrong too.** If you're confident in your
   method after steps 1–3, write down your answer and your reasoning and raise
   it. A disagreement is worth looking into either way. It's how the
   evaluation set gets better.

## What's in this folder

```
eval/truth/
├── README.md        this guide
├── q01.R … q20.R    practice files (you fill these in)
└── key/
    ├── check.R      check_answer(id, answer): PASS/FAIL against the key
    └── key.rds      the hidden answers (don't open it; it's stored scrambled)
```

## Good to know

- **The key matches the data as downloaded on 21 Oct 2026.** If you rerun the
  ingest scripts and NHS England has revised past months, some answers may
  change and correct code could FAIL. The key would then need rebuilding.
- `check_answer` grades by type. Numbers pass within 1%. Counts, rankings and
  yes/no must match exactly. Rankings must list the same codes in the same
  order.
- Percentages are answered as a number of percent: `65.2`, not `0.652`.

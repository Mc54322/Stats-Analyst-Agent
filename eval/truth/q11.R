# q11 ---------------------------------------------------------------------
# Question: By how much did England's total A&E attendances (attendances_total,
#   all providers) change from Oct 2024 to Sep 2026? Give Sep 2026 minus Oct 2024.
# Answer looks like: one number (attendances). Negative would mean a fall.
# Gotcha from notes.md: none directly, but note the A&E table starts in
#   Oct 2024, one month later than RTT ("Different months").
#
# Plan:
#   1. Total attendances for Oct 2024 (filter the month, then sum).
#   2. Total attendances for Sep 2026 (the same steps, different month).
#   3. Subtract: Sep 2026 minus Oct 2024.
#
# Tools you'll need:
#   filter()     keeps rows that match.
#   summarise()  squashes rows into one row of results.
#   sum()        adds numbers up.
#   pull()       takes one column out as a plain value.
#   <-           saves a result under a name.
#
# Fill in each .___ (there are 4 blanks). Blank 3 is a whole pipeline.
# --------------------------------------------------------------------------

library(dplyr)
library(arrow)
source("eval/truth/key/check.R")

ae <- read_parquet("data/clean/ae_provider.parquet")

total_oct24 <- ae |>
  filter(period == .___) |>             # blank 1
  summarise(total = .___) |>            # blank 2
  pull(total)

total_sep26 <- .___                     # blank 3

total_oct24                            # check both totals look sensible
total_sep26

answer <- .___                          # blank 4

answer
check_answer("q11", answer)

# Hints ---------------------------------------------------------------------
# Hint 1: The first month of the A&E table, written as a date.
# Hint 2: Add up the attendances column inside summarise().
# Hint 3: Copy the whole total_oct24 pipeline (ae |> ... |> pull(total)) and
#         change only the month.
# Hint 4: Later month minus earlier month.

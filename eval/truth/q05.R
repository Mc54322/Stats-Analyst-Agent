# q05 ---------------------------------------------------------------------
# Question: Across all providers in the A&E table, how many patients waited
#   over 12 hours from decision to admit to admission (dta_wait_over_12hrs)
#   in Sep 2026?
# Answer looks like: one number (patients).
# Gotcha from notes.md: "dta_wait_over_12hrs is measured from the decision to
#   admit, not from arrival." These are trolley waits, not 12 hours in A&E.
#
# Plan:
#   1. Keep the A&E rows for Sep 2026 (one row per provider).
#   2. Add up dta_wait_over_12hrs across all those rows.
#   3. Take the total out as a plain number.
#
# Tools you'll need:
#   filter()     keeps rows that match.
#   summarise()  NEW: squashes many rows into one row of results.
#                `summarise(total = sum(x))` makes a column called total.
#   sum()        adds numbers up.
#   pull()       takes one column out as a plain value.
#
# Fill in each .___ (there are 2 blanks).
# --------------------------------------------------------------------------

library(dplyr)
library(arrow)
source("eval/truth/key/check.R")

ae <- read_parquet("data/clean/ae_provider.parquet")

answer <- ae |>
  filter(period == .___) |>                          # blank 1
  summarise(total = .___(dta_wait_over_12hrs)) |>    # blank 2
  pull(total)

answer
check_answer("q05", answer)

# Hints ---------------------------------------------------------------------
# Hint 1: This is the whole date check, not just the text. q01 has an example.
# Hint 2: Which function from the Tools list adds numbers up?

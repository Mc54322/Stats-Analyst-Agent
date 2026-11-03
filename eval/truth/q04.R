# q04 ---------------------------------------------------------------------
# Question: How many providers in the A&E table for Sep 2026 had no A&E
#   attendances at all (has_ae_activity is FALSE)?
# Answer looks like: a whole number (providers). Must match exactly.
# Gotcha from notes.md: "Many providers aren't hospitals." Some report no
#   attendances at all, and their pct_* columns are NA.
#
# Plan:
#   1. Keep the A&E rows for Sep 2026 where has_ae_activity is FALSE.
#   2. Count the rows (one row = one provider in a month).
#
# Tools you'll need:
#   filter()   keeps rows that match.
#   nrow()     counts the rows in a table. You used it in q03.
#
# Fill in each .___ (there are 2 blanks).
# --------------------------------------------------------------------------

library(dplyr)
library(arrow)
source("eval/truth/key/check.R")

ae <- read_parquet("data/clean/ae_provider.parquet")

answer <- ae |>
  filter(period == as.Date("2026-09-01"), has_ae_activity == .___) |>   # blank 1
  .___()                                                                 # blank 2

answer
check_answer("q04", answer)

# Hints ---------------------------------------------------------------------
# Hint 1: You want the providers with no activity. It's a TRUE/FALSE value.
# Hint 2: The function that counts rows. q03 used it.

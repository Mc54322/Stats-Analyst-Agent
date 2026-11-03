# q01 ---------------------------------------------------------------------
# Question: How many A&E attendances in total (attendances_total) did Oxford
#   University Hospitals NHS Foundation Trust (org_code RTH) have in Sep 2026?
# Answer looks like: one number (attendances).
# Gotcha from notes.md: none for this one. It's a warm-up.
#
# Plan:
#   1. Start from the A&E table.
#   2. Keep only the row for Sep 2026 and org_code RTH.
#   3. Take the attendances_total value out of that row.
#
# Tools you'll need:
#   |>         "and then": passes the result of one step into the next.
#   filter()   keeps only the rows that match your conditions.
#   pull()     takes one column out of a table as a plain value.
#   as.Date()  turns text like "2026-09-01" into a date. Every month is
#              stored as the 1st of the month.
#
# Fill in each .___ (there is 1 blank), then run the file top to bottom.
# A blank looks like .___ (dot plus three underscores). Replace the whole
# thing, dot included, with your code. If you run a line that still has a
# blank, R tells you so.
# --------------------------------------------------------------------------

library(dplyr)
library(arrow)
source("eval/truth/key/check.R")

ae <- read_parquet("data/clean/ae_provider.parquet")

answer <- ae |>
  filter(period == as.Date("2026-09-01"), org_code == .___) |>   # blank 1
  pull(attendances_total)

answer
check_answer("q01", answer)

# Hints ---------------------------------------------------------------------
# Hint 1: org_code holds text, and text in R always goes inside quotes.

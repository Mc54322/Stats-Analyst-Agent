# q08 ---------------------------------------------------------------------
# Question: In Sep 2026, what percentage of all A&E attendances in England (all
#   types, booked appointments included) were 4 hours or less? Use every
#   provider in the A&E table.
# Answer looks like: a percentage as a number (74.4 means 74.4%).
# Gotcha from notes.md (TRAP): "Percentages: always use the ratio of sums,
#   never mean() of the pct_* columns." Averaging each provider's percentage
#   makes small walk-in centres count as much as big hospitals.
#
# Plan:
#   1. Keep Sep 2026.
#   2. Add up attendances_total and over_4hrs_total across all providers.
#   3. % within 4 hours = 100 * (1 - over 4 hours / attendances).
#
# Tools you'll need:
#   summarise()  squashes rows into one row. It can make several columns at once.
#   mutate()     NEW: adds a column calculated from other columns.
#   sum()        adds numbers up.
#   /  *  -      divide, multiply, subtract.
#
# Fill in each .___ (there are 3 blanks).
# --------------------------------------------------------------------------

library(dplyr)
library(arrow)
source("eval/truth/key/check.R")

ae <- read_parquet("data/clean/ae_provider.parquet")

answer <- ae |>
  filter(period == as.Date("2026-09-01")) |>
  summarise(
    attendances = sum(attendances_total),
    over_4hrs   = sum(.___)                    # blank 1
  ) |>
  mutate(pct = 100 * (1 - .___ / .___)) |>      # blanks 2 and 3
  pull(pct)

answer
check_answer("q08", answer)

# Try this after you PASS: compare with
#   ae |> filter(period == as.Date("2026-09-01")) |>
#     summarise(m = 100 * mean(pct_within_4hrs, na.rm = TRUE))
# That's the wrong (averaged) answer the trap is about.

# Hints ---------------------------------------------------------------------
# Hint 1: The column counting all attendances over 4 hours. Its name mirrors
#         attendances_total.
# Hint 2: The new name you gave the over-4-hours sum inside summarise().
# Hint 3: The new name you gave the attendances sum inside summarise().

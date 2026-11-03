# q07 ---------------------------------------------------------------------
# Question: What was the England total of incomplete RTT pathways in Aug 2026,
#   as recorded in the RTT table (all providers, all specialties)?
# Answer looks like: one number (pathways).
# Gotcha from notes.md (TRAP): "C_999 (Total) rows sit next to the specialty
#   rows. Never sum both; that doubles the count." "All specialties" means the
#   C_999 rows, not every row.
#
# Plan:
#   1. Keep Aug 2026 and ONLY the all-specialty total rows.
#   2. Add up total_incomplete across all providers.
#   3. Take the total out as a plain number.
#
# Tools you'll need:
#   filter()     keeps rows that match. A whole condition such as
#                `is_all_specialties_total == TRUE` goes inside.
#   summarise()  squashes rows into one row of results.
#   sum()        adds numbers up.
#   pull()       takes one column out as a plain value.
#
# Fill in each .___ (there are 2 blanks).
# --------------------------------------------------------------------------

library(dplyr)
library(arrow)
source("eval/truth/key/check.R")

rtt <- read_parquet("data/clean/rtt_incomplete_provider.parquet")

answer <- rtt |>
  filter(period == as.Date("2026-08-01"), .___) |>    # blank 1
  summarise(total = sum(.___)) |>                     # blank 2
  pull(total)

answer
check_answer("q07", answer)

# Try this after you PASS: delete blank 1's condition and run again. How much
# bigger is the answer? That's the trap.

# Hints ---------------------------------------------------------------------
# Hint 1: A full condition (column, ==, value) that keeps only the total rows.
#         q02 used the same idea.
# Hint 2: The column holding the number of incomplete pathways.

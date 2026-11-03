# q13 ---------------------------------------------------------------------
# Question: What percentage of England's incomplete RTT pathways with a known
#   clock start had waited 18 weeks or less in Aug 2026? Use the C_999 rows for
#   all providers.
# Answer looks like: a percentage as a number (65.2 means 65.2%).
# Gotcha from notes.md (TRAP): "Percentages: always use the ratio of sums,
#   never mean() of the pct_* columns." Don't touch pct_within_18_weeks.
#
# Plan:
#   1. Keep Aug 2026 and the C_999 rows.
#   2. Add up within_18_weeks and known_clock_start across all providers.
#   3. Percentage = 100 * within-18-weeks total / known-clock-start total.
#
# Tools you'll need:
#   filter()     keeps rows that match.
#   summarise()  squashes rows into one row. Make two sums with two names.
#   mutate()     adds a column calculated from other columns.
#   pull()       takes one column out as a plain value.
#
# Fill in each .___() (there are 3 blanks). Each blank is a whole step now:
# replace .___() with one complete function call, such as filter(...).
# Look back at q08 and q10 if you get stuck; this is the same shape.
# --------------------------------------------------------------------------

library(dplyr)
library(arrow)
source("eval/truth/key/check.R")

rtt <- read_parquet("data/clean/rtt_incomplete_provider.parquet")

answer <- rtt |>
  .___() |>                  # blank 1
  .___() |>                  # blank 2
  .___() |>                  # blank 3 (make a column called pct)
  pull(pct)

answer
check_answer("q13", answer)

# Hints ---------------------------------------------------------------------
# Hint 1: One filter() with two conditions, the same as q10.
# Hint 2: One summarise() that creates two sums. Give each a short name.
# Hint 3: One mutate() that makes pct from the two names you just created.
#         No "1 -" this time: you already have the "18 weeks or less" count.

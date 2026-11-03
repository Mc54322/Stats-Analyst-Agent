# q09 ---------------------------------------------------------------------
# Question: In Sep 2026, how many percentage points higher was England's
#   all-types 4-hour performance than its Type 1 4-hour performance? Calculate
#   both as ratios of sums across every provider in the A&E table, then
#   subtract (all-types minus Type 1).
# Answer looks like: a number (percentage points).
# Gotcha from notes.md: "Two different 4-hour measures." All types (headline)
#   vs Type 1 (major A&E only). For Type 1, use the *_type1_all columns, which
#   include Type 1 booked appointments.
#
# Plan:
#   1. Keep Sep 2026 (done for you, saved as sep26).
#   2. All-types % within 4 hours (done for you, the same formula as q08).
#   3. Type 1 % within 4 hours: the same formula with
#      over_4hrs_type1_all and attendances_type1_all.
#   4. Subtract: all-types minus Type 1.
#
# Tools you'll need:
#   summarise()  squashes rows into one row. You can do maths right inside it.
#   sum()        adds numbers up.
#   pull()       takes one column out as a plain value.
#
# Fill in each .___ (there are 2 blanks).
# --------------------------------------------------------------------------

library(dplyr)
library(arrow)
source("eval/truth/key/check.R")

ae <- read_parquet("data/clean/ae_provider.parquet")

sep26 <- ae |> filter(period == as.Date("2026-09-01"))

all_types <- sep26 |>
  summarise(pct = 100 * (1 - sum(over_4hrs_total) / sum(attendances_total))) |>
  pull(pct)

type1 <- sep26 |>
  summarise(pct = .___) |>        # blank 1
  pull(pct)

all_types                        # run these to see both percentages
type1

answer <- .___                    # blank 2

answer
check_answer("q09", answer)

# Hints ---------------------------------------------------------------------
# Hint 1: Copy the formula from all_types and swap in the two Type 1 column
#         names from the Plan.
# Hint 2: The two names you saved, in the order the question asks.

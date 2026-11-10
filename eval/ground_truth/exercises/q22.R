# q22 ---------------------------------------------------------------------
# Question: Rank all 7 NHS England regions (parent_org in the A&E table) by
#   all-types 4-hour performance in Sep 2026, lowest first. Calculate each
#   region's performance as a ratio of sums across all its providers:
#   1 - sum(over_4hrs_total) / sum(attendances_total). List the parent_org names.
# Answer looks like: 7 region names in order, e.g. c("NHS ENGLAND ...", ...).
# Gotcha from notes.md: "Percentages: always use the ratio of sums, never
#   mean() of the pct_* columns."
#
# Plan:
#   1. Keep Sep 2026.
#   2. Group by region.
#   3. Add up attendances and over-4-hour attendances per region.
#   4. Work out each region's percentage within 4 hours.
#   5. Sort lowest first and take out the region names.
#
# Tools you'll need:
#   filter(), group_by(), summarise(), sum(), mutate(), arrange(), pull()
#
# Fill in each .___ (there are 4 blanks).
# --------------------------------------------------------------------------

library(dplyr)
library(arrow)
source("eval/ground_truth/exercises/check.R")

ae <- read_parquet("data/clean/ae_provider.parquet")

answer <- ae |>
  filter(period == as.Date("2026-09-01")) |>
  group_by(.___) |>                                           # blank 1
  summarise(attendances = sum(attendances_total),
            over_4hrs   = sum(over_4hrs_total)) |>
  mutate(pct = .___) |>                                       # blank 2
  arrange(.___) |>                                            # blank 3
  pull(.___)                                                  # blank 4

answer
check_answer("q22", answer)

# Hints ---------------------------------------------------------------------
# Hint 1: The column holding the region.
# Hint 2: The same shape as q08: 100 * (1 - one sum / the other).
# Hint 3: Lowest first is arrange()'s default.
# Hint 4: The column you grouped by.

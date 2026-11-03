# q03 ---------------------------------------------------------------------
# Question: Does Sheffield Teaching Hospitals NHS Foundation Trust
#   (provider_org_code RHQ) have any rows in the RTT table for Aug 2026?
# Answer looks like: yes or no (TRUE or FALSE also works).
# Gotcha from notes.md: "Missing submissions." Some trusts stop sending data.
#   If a trust has no rows for a month, it isn't in the totals for that month.
#
# Plan:
#   1. Keep the RTT rows for provider RHQ in Aug 2026.
#   2. Count how many rows are left.
#   3. The answer is "yes" if that count is more than zero.
#
# Tools you'll need:
#   filter()   keeps rows that match.
#   nrow()     counts the rows in a table.
#   >          "greater than". `5 > 0` gives TRUE, `0 > 0` gives FALSE.
#
# Fill in each .___ (there is 1 blank).
# --------------------------------------------------------------------------

library(dplyr)
library(arrow)
source("eval/truth/key/check.R")

rtt <- read_parquet("data/clean/rtt_incomplete_provider.parquet")

rows_found <- rtt |>
  filter(provider_org_code == "RHQ", period == as.Date("2026-08-01")) |>
  nrow()

rows_found                      # run this line to see the count

answer <- .___                  # blank 1

answer
check_answer("q03", answer)

# Hints ---------------------------------------------------------------------
# Hint 1: Write a comparison: rows_found, then a symbol, then 0. You want TRUE
#         when rows_found is bigger than zero. Which symbol from the Tools list
#         does that?

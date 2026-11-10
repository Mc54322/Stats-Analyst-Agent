# q21 ---------------------------------------------------------------------
# Question: In Aug 2026, which 3 ICBs had the most incomplete RTT pathways?
#   Build ICB totals from provider data: sum the C_999 rows of every provider,
#   grouped by the provider's provider_parent_org_code in Aug 2026. List the
#   3 provider_parent_org_code values, highest first.
# Answer looks like: 3 codes in order, e.g. c("AAA", "BBB", "CCC").
# Gotchas from notes.md: "C_999 (Total) rows sit next to the specialty rows"
#   and "provider_parent_* is the ICB, not the region". Use the Aug 2026 parent
#   code, since a provider's parent ICB can change over time.
#
# Plan:
#   1. Keep Aug 2026 and only the C_999 rows.
#   2. Group by the ICB code.
#   3. Add up total_incomplete for each ICB.
#   4. Sort biggest first, keep 3, and take out the ICB codes.
#
# Tools you'll need:
#   filter(), group_by(), summarise(), sum(), arrange(), desc(), head(), pull()
#
# Fill in each .___ (there are 4 blanks).
# --------------------------------------------------------------------------

library(dplyr)
library(arrow)
source("eval/ground_truth/exercises/check.R")

rtt <- read_parquet("data/clean/rtt_incomplete_provider.parquet")

answer <- rtt |>
  filter(period == as.Date("2026-08-01"), .___) |>      # blank 1
  group_by(.___) |>                                      # blank 2
  summarise(pathways = sum(total_incomplete)) |>
  arrange(.___) |>                                       # blank 3
  head(3) |>
  pull(.___)                                             # blank 4

answer
check_answer("q21", answer)

# Hints ---------------------------------------------------------------------
# Hint 1: The condition that keeps only the all-specialty total rows.
# Hint 2: The column holding the ICB code (not the ICB name).
# Hint 3: Biggest first, on the column you made in summarise().
# Hint 4: The same column you grouped by.

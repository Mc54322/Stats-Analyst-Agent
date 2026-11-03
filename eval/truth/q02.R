# q02 ---------------------------------------------------------------------
# Question: How many incomplete RTT pathways did Oxford University Hospitals
#   NHS Foundation Trust (provider_org_code RTH) have across all specialties
#   (its C_999 row) in Aug 2026?
# Answer looks like: one number (pathways).
# Gotcha from notes.md: "C_999 (Total) rows sit next to the specialty rows."
#   RTH has one row per specialty plus one C_999 total row. You want the total row.
#
# Plan:
#   1. Start from the RTT table.
#   2. Keep only Aug 2026, provider RTH, and the all-specialty total row.
#   3. Take total_incomplete out of that row.
#
# Tools you'll need:
#   |>         "and then": passes the result into the next step.
#   filter()   keeps rows that match. Separate several conditions with commas.
#   pull()     takes one column out as a plain value.
#   as.Date()  turns "2026-08-01" into a date.
#   TRUE/FALSE R's yes/no values (no quotes).
#
# Fill in each .___ (there are 2 blanks).
# --------------------------------------------------------------------------

library(dplyr)
library(arrow)
source("eval/truth/key/check.R")

rtt <- read_parquet("data/clean/rtt_incomplete_provider.parquet")

answer <- rtt |>
  filter(period == as.Date(.___),                 # blank 1
         provider_org_code == "RTH",
         is_all_specialties_total == .___) |>     # blank 2
  pull(total_incomplete)

answer
check_answer("q02", answer)

# Hints ---------------------------------------------------------------------
# Hint 1: Look at how q01 wrote Sep 2026. Aug 2026 follows the same pattern.
# Hint 2: is_all_specialties_total is TRUE on the C_999 row. Should the value
#         you compare against have quotes?

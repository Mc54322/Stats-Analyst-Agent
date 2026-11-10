# q27 ---------------------------------------------------------------------
# Question: Royal Free London (RAL) took over North Middlesex (RAP) in Jan 2025.
#   Comparing like for like, what is the change in incomplete RTT pathways from
#   Oct 2024 (RAL plus RAP, their C_999 rows) to Aug 2026 (RAL's C_999 row)?
#   Give Aug 2026 minus Oct 2024.
# Answer looks like: one number (pathways). Negative means a fall.
# Gotcha from notes.md: "Mergers break provider time series." Comparing RAL
#   alone would count RAP's patients as growth.
#
# Plan:
#   1. Keep the C_999 rows.
#   2. Before: total for RAL and RAP together in Oct 2024.
#   3. After: total for RAL in Aug 2026.
#   4. Subtract: after minus before.
#
# Tools you'll need:
#   filter(), summarise(), sum(), pull(), %in% (q18)
#
# Fill in each .___ (there are 4 blanks). Blank 3 is a whole pipeline.
# --------------------------------------------------------------------------

library(dplyr)
library(arrow)
source("eval/ground_truth/exercises/check.R")

rtt <- read_parquet("data/clean/rtt_incomplete_provider.parquet")
c999 <- rtt |> filter(is_all_specialties_total)

before <- c999 |>
  filter(period == .___, provider_org_code %in% .___) |>       # blanks 1 and 2
  summarise(total = sum(total_incomplete)) |>
  pull(total)

after <- .___                                                 # blank 3

before
after

answer <- .___                                                # blank 4

answer
check_answer("q27", answer)

# Hints ---------------------------------------------------------------------
# Hint 1: The "before" month, written as a date.
# Hint 2: Both provider codes, as a vector with c().
# Hint 3: Copy the "before" pipeline; change the month, and the codes to just RAL.
# Hint 4: The question says which comes first.

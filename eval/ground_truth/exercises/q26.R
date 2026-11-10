# q26 ---------------------------------------------------------------------
# Question: In Aug 2026, consider NHS trusts (3-character code starting with R
#   or T) that appear both in the RTT table (C_999 row) and in the A&E table
#   with Type 1 attendances (attendances_type1_all > 0). How many have more than
#   70,000 incomplete pathways AND a Type 1 4-hour performance below 60%?
#   Type 1 4-hour performance = 100 * (1 - over_4hrs_type1_all / attendances_type1_all).
# Answer looks like: a whole number (trusts). Must match exactly.
# Gotchas from notes.md: "Joining RTT to A&E loses providers" (only trusts in
#   both count here) and "NHS trust vs other providers".
#
# Plan:
#   1. RTT: Aug 2026, C_999 rows, NHS trusts only; keep code and pathways.
#   2. A&E: Aug 2026, providers with Type 1 attendances; work out Type 1 %.
#   3. Join the two on the code, keeping only trusts in both.
#   4. Count trusts over both thresholds.
#
# Tools you'll need:
#   filter(), mutate(), select(), grepl() (q15), nrow()
#   select(new = old)  NEW: keeps columns, and can rename them as it goes.
#   inner_join(a, b, by = "col")  NEW: keeps only rows whose col value is in
#                      both tables, and puts their columns side by side.
#
# Fill in each .___ (there are 5 blanks).
# --------------------------------------------------------------------------

library(dplyr)
library(arrow)
source("eval/ground_truth/exercises/check.R")

rtt <- read_parquet("data/clean/rtt_incomplete_provider.parquet")
ae  <- read_parquet("data/clean/ae_provider.parquet")

rtt_trusts <- rtt |>
  filter(period == as.Date("2026-08-01"), is_all_specialties_total,
         grepl(.___, provider_org_code)) |>                       # blank 1
  select(org_code = provider_org_code, pathways = total_incomplete)

ae_type1 <- ae |>
  filter(period == as.Date("2026-08-01"), .___) |>                # blank 2
  mutate(pct_type1 = .___) |>                                     # blank 3
  select(org_code, pct_type1)

both <- .___(rtt_trusts, ae_type1, by = "org_code")               # blank 4
nrow(both)                                                        # trusts in both tables

answer <- both |> filter(.___) |> nrow()                          # blank 5

answer
check_answer("q26", answer)

# Hints ---------------------------------------------------------------------
# Hint 1: The NHS trust pattern from notes.md (q15 used it).
# Hint 2: The condition for "has Type 1 attendances".
# Hint 3: The formula in the question, using the two Type 1 columns.
# Hint 4: The join that keeps only codes found in both tables.
# Hint 5: Two conditions, one per threshold. In R, 70,000 is written 70000.

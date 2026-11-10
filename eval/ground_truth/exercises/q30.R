# q30 ---------------------------------------------------------------------
# Question: Among NHS trusts that have a C_999 row in every one of the 24 RTT
#   months, excluding the trusts involved in mergers (RA7, RVJ, RAL, RAP),
#   which 3 had the largest percentage fall in incomplete pathways from Sep 2024
#   to Aug 2026? List their provider_org_code values, largest fall first.
#   Percentage change = (Aug 2026 - Sep 2024) / Sep 2024.
# Answer looks like: 3 codes in order, e.g. c("AAA", "BBB", "CCC").
# Gotchas from notes.md: "Mergers break provider time series", "Missing
#   submissions", "NHS trust vs other providers".
#
# Plan:
#   1. Keep the C_999 rows.
#   2. Find the providers present in all 24 months (as in q28).
#   3. Keep NHS trusts among them, and drop RA7, RVJ, RAL and RAP.
#   4. For each trust, get its Sep 2024 and Aug 2026 totals.
#   5. Work out the percentage change, sort with the biggest fall first, keep 3.
#
# Tools you'll need:
#   count(), filter(), grepl(), %in%, ! (means "not"), mutate(), arrange(), head(), pull()
#   One way to put both months side by side: make one table per month with
#   select(code = provider_org_code, sep24 = total_incomplete) (and aug26 for
#   the other), then inner_join() them by code (q26).
#
# Write the code yourself, following the plan.
# --------------------------------------------------------------------------

library(dplyr)
library(arrow)
source("eval/ground_truth/exercises/check.R")

rtt <- read_parquet("data/clean/rtt_incomplete_provider.parquet")

answer <- .___

answer
check_answer("q30", answer)

# Hints (one per Plan step) -------------------------------------------------
# Step 1: The filter you've used since q07.
# Step 2: count(), then keep n == 24 (q28).
# Step 3: grepl() with the trust pattern, and !provider_org_code %in% c(...).
# Step 4: Two filtered tables (one per month), joined by code.
# Step 5: A biggest fall is the most negative change, so sort smallest first.

# q20 ---------------------------------------------------------------------
# Question: Among NHS trusts with at least 10,000 incomplete RTT pathways in
#   Aug 2026 (C_999 row), which 5 had the lowest percentage waiting 18 weeks or
#   less? Use within_18_weeks divided by known_clock_start. List their
#   provider_org_code values, lowest first.
# Answer looks like: 5 provider codes in order, e.g. c("AAA", "BBB", ...).
# Gotchas from notes.md: "C_999 (Total) rows sit next to the specialty rows"
#   and "NHS trust vs other providers: a 3-character ODS code starting with R or T."
#
# Plan:
#   1. Keep Aug 2026, the C_999 rows, and only NHS trusts.
#   2. Keep trusts with total_incomplete of at least 10,000.
#   3. Work out each trust's within_18_weeks / known_clock_start.
#   4. Sort lowest first, keep the top 5, and take out the codes.
#
# Tools you'll need:
#   filter(), grepl() (q15), mutate(), arrange() (smallest first by default),
#   head(), pull()
#   >=   "at least" (greater than or equal to).
#
# Write the code yourself. This one pulls together most of what you've learned.
# --------------------------------------------------------------------------

library(dplyr)
library(arrow)
source("eval/truth/key/check.R")

rtt <- read_parquet("data/clean/rtt_incomplete_provider.parquet")

answer <- .___

answer
check_answer("q20", answer)

# Hints (one per Plan step) -------------------------------------------------
# Step 1: Three conditions in one filter(). The trust pattern is the same as q15.
# Step 2: A fourth condition, using >=. In R, 10,000 is written 10000 (no comma).
# Step 3: Per-trust maths goes in mutate(), not summarise(), because you want
#         one value per row.
# Step 4: Lowest first is arrange()'s default, so no desc() this time.

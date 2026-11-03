# q19 ---------------------------------------------------------------------
# Question: Barking, Havering and Redbridge (RF4) did not submit RTT data for
#   Nov 2025. What was the like-for-like change in England's incomplete RTT
#   pathways from Oct 2025 to Nov 2025, counting only providers that have a
#   C_999 row in both months? Give Nov minus Oct.
# Answer looks like: one number (pathways). Negative means a fall.
# Gotcha from notes.md (TRAP): "Missing submissions... A month-on-month drop
#   may be a gap in submissions, not a real fall." Comparing the raw national
#   totals would count RF4's missing ~72k as a fall.
#
# Plan:
#   1. Keep the C_999 rows for Oct 2025, and separately for Nov 2025.
#   2. Find the provider codes that appear in BOTH months.
#   3. Total total_incomplete for those providers in Oct 2025.
#   4. Total total_incomplete for those providers in Nov 2025.
#   5. Subtract: Nov minus Oct.
#
# Tools you'll need:
#   filter(), summarise(), sum(), pull(), <-, %in% (q18)
#   intersect(a, b)  NEW: the values that are in both a and b.
#   pull()           also gives you a list of codes when there are many rows.
#
# Write the code yourself, one or two lines per Plan step.
# --------------------------------------------------------------------------

library(dplyr)
library(arrow)
source("eval/truth/key/check.R")

rtt <- read_parquet("data/clean/rtt_incomplete_provider.parquet")

.___

answer <- .___

answer
check_answer("q19", answer)

# Hints (one per Plan step) -------------------------------------------------
# Step 1: Two saved tables, one per month, each filtered to the total rows.
# Step 2: pull() the code column from each table, then intersect() the two lists.
# Step 3: filter() the Oct table with %in% on your shared codes, then sum.
# Step 4: The same as step 3, using the Nov table.
# Step 5: Later minus earlier. Bonus: compare with the plain national change.

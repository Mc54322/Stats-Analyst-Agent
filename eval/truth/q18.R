# q18 ---------------------------------------------------------------------
# Question: North Bristol NHS Trust (RVJ) merged into RA7 in Jul 2026. Compare
#   like for like across the merger. Take RA7's incomplete pathways in Jul 2026
#   (C_999 row) and subtract the combined incomplete pathways of RA7 and RVJ in
#   Jun 2026 (their C_999 rows). What is the result?
# Answer looks like: one number (pathways). It can be small or negative.
# Gotcha from notes.md (TRAP): "Mergers break provider time series." RA7 alone
#   "jumps" in Jul 2026 because it absorbed RVJ. That isn't a real rise.
#
# Plan:
#   1. Keep the C_999 rows.
#   2. RA7's total_incomplete in Jul 2026 (one number).
#   3. RA7 plus RVJ in Jun 2026: keep both providers for Jun 2026 and add them up.
#   4. Subtract: step 2 minus step 3.
#
# Tools you'll need:
#   filter(), summarise(), sum(), pull(), <-
#   %in%   NEW: TRUE where a value is one of a set,
#          e.g. provider_org_code %in% c("RA7", "RVJ").
#
# Write the code yourself. Saving steps 2 and 3 under names makes step 4 easy.
# --------------------------------------------------------------------------

library(dplyr)
library(arrow)
source("eval/truth/key/check.R")

rtt <- read_parquet("data/clean/rtt_incomplete_provider.parquet")

.___

answer <- .___

answer
check_answer("q18", answer)

# Hints (one per Plan step) -------------------------------------------------
# Step 1: The same total-row filter you've used since q07. Save it for reuse.
# Step 2: Two conditions: the provider and the month.
# Step 3: Use %in% for the two providers, then sum like q07.
# Step 4: After minus before.

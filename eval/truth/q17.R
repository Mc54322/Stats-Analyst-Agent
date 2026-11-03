# q17 ---------------------------------------------------------------------
# Question: In Sep 2026, what percentage of England's A&E attendances
#   (attendances_total, all providers) led to an emergency admission via A&E?
# Answer looks like: a percentage as a number (16.0 means 16.0%).
# Gotcha from notes.md (TRAP): "emergency_admissions_total includes admissions
#   that didn't come through A&E. For A&E conversion rates use
#   emergency_admissions_via_ae / attendances_total."
#
# Plan:
#   1. Keep Sep 2026.
#   2. Add up emergency_admissions_via_ae and attendances_total.
#   3. Percentage = 100 * admissions via A&E / attendances.
#
# Tools you'll need:
#   filter(), summarise(), sum(), mutate(), pull(). All used before (see q08).
#
# Write the code yourself, one line per Plan step.
# --------------------------------------------------------------------------

library(dplyr)
library(arrow)
source("eval/truth/key/check.R")

ae <- read_parquet("data/clean/ae_provider.parquet")

answer <- .___

answer
check_answer("q17", answer)

# Hints (one per Plan step) -------------------------------------------------
# Step 1: Just the month. Every provider counts.
# Step 2: Check the column name carefully. It's the one that ends in _via_ae.
# Step 3: The same shape as q13's last step.

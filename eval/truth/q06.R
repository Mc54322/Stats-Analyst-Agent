# q06 ---------------------------------------------------------------------
# Question: How many more distinct RTT providers (provider_org_code, counted on
#   the C_999 rows) were there in Aug 2026 than in Sep 2024?
#   Give the Aug 2026 count minus the Sep 2024 count.
# Answer looks like: a whole number (providers). Must match exactly.
# Gotcha from notes.md: "More providers over time." The count grows, mostly
#   from independent-sector providers joining.
#
# Plan:
#   1. Count the distinct providers on the C_999 rows in Aug 2026 (done for you).
#   2. Do the same for Sep 2024.
#   3. Subtract: Aug 2026 minus Sep 2024.
#
# Tools you'll need:
#   filter()       keeps rows that match.
#   summarise()    squashes rows into one row of results.
#   n_distinct()   NEW: counts how many different values a column has.
#   pull()         takes one column out as a plain value.
#   <-             saves a result under a name so you can use it later.
#   -              subtracts one number from another.
#
# Fill in each .___ (there are 3 blanks).
# --------------------------------------------------------------------------

library(dplyr)
library(arrow)
source("eval/truth/key/check.R")

rtt <- read_parquet("data/clean/rtt_incomplete_provider.parquet")

providers_aug26 <- rtt |>
  filter(period == as.Date("2026-08-01"), is_all_specialties_total == TRUE) |>
  summarise(n = n_distinct(provider_org_code)) |>
  pull(n)

providers_sep24 <- rtt |>
  filter(period == .___, is_all_specialties_total == TRUE) |>   # blank 1
  summarise(n = .___(provider_org_code)) |>                     # blank 2
  pull(n)

providers_aug26                 # run these two lines to see both counts
providers_sep24

answer <- .___                   # blank 3

answer
check_answer("q06", answer)

# Hints ---------------------------------------------------------------------
# Hint 1: The first month in the RTT table. Copy the date pattern from above.
# Hint 2: The same counting function as in the Aug 2026 block just above.
# Hint 3: Use the two names you saved. Which one comes first in "Aug minus Sep"?

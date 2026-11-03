# q14 ---------------------------------------------------------------------
# Question: How many RTT providers (provider_org_code) have more than one
#   distinct provider_parent_org_code across all 24 months? Use the C_999 rows.
# Answer looks like: a whole number (providers). Must match exactly.
# Gotcha from notes.md: "A provider's parent ICB can change over time." Mostly
#   from the Apr 2026 ICB mergers.
#
# Plan:
#   1. Keep the C_999 rows (all months).
#   2. Group by provider, so the next step works one provider at a time.
#   3. For each provider, count its distinct parent codes.
#   4. Keep providers with more than one, and count them.
#
# Tools you'll need:
#   group_by()    NEW: splits the table into groups. The next summarise()
#                 gives one row per group instead of one row overall.
#   summarise()   with group_by(), gives one result row per group.
#   n_distinct()  counts how many different values a column has (q06).
#   filter()      keeps rows that match. Here it runs on the summary rows.
#   nrow()        counts rows.
#
# Fill in each .___ (there are 3 blanks).
# --------------------------------------------------------------------------

library(dplyr)
library(arrow)
source("eval/truth/key/check.R")

rtt <- read_parquet("data/clean/rtt_incomplete_provider.parquet")

answer <- rtt |>
  filter(is_all_specialties_total == TRUE) |>
  group_by(.___) |>                                           # blank 1
  summarise(n_parents = .___(provider_parent_org_code)) |>    # blank 2
  filter(.___) |>                                             # blank 3
  nrow()

answer
check_answer("q14", answer)

# Try this: run the pipeline without the last two lines to see the
# per-provider table that group_by() + summarise() makes.

# Hints ---------------------------------------------------------------------
# Hint 1: The column that identifies a provider (group by the code, not the name).
# Hint 2: The function that counts different values.
# Hint 3: A condition on n_parents that means "more than one".

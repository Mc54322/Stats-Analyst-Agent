# q12 ---------------------------------------------------------------------
# Question: By how much did the number of RTT pathways in England waiting more
#   than 52 weeks change from Sep 2024 to Aug 2026? Use the C_999 rows for all
#   providers and give Aug 2026 minus Sep 2024 (negative means a fall).
# Answer looks like: one number (pathways).
# Gotcha from notes.md: "C_999 (Total) rows sit next to the specialty rows."
#   Filter to them once and reuse the result.
#
# Plan:
#   1. Keep only the C_999 rows and save them (call it c999).
#   2. From c999, total over_52_weeks for Sep 2024.
#   3. From c999, total over_52_weeks for Aug 2026.
#   4. Subtract: Aug 2026 minus Sep 2024.
#
# Tools you'll need:
#   filter()     keeps rows that match.
#   summarise()  squashes rows into one row of results.
#   sum()        adds numbers up.
#   pull()       takes one column out as a plain value.
#
# Fill in each .___ (there are 4 blanks). Blanks 2 and 3 are bigger.
# --------------------------------------------------------------------------

library(dplyr)
library(arrow)
source("eval/truth/key/check.R")

rtt <- read_parquet("data/clean/rtt_incomplete_provider.parquet")

c999 <- rtt |> filter(.___)                   # blank 1

over52_sep24 <- c999 |>
  .___() |>                                     # blank 2
  summarise(total = sum(over_52_weeks)) |>
  pull(total)

over52_aug26 <- .___                          # blank 3

over52_sep24
over52_aug26

answer <- .___                                # blank 4

answer
check_answer("q12", answer)

# Hints ---------------------------------------------------------------------
# Hint 1: The condition that keeps only the all-specialty total rows.
# Hint 2: Replace .___() with a whole filter() step that keeps only Sep 2024.
# Hint 3: Copy the over52_sep24 pipeline and change the month.
# Hint 4: The question says which comes first.

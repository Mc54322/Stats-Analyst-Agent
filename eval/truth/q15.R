# q15 ---------------------------------------------------------------------
# Question: Which 5 NHS trusts had the most Type 1 A&E attendances including
#   Type 1 booked appointments (attendances_type1_all) in Sep 2026? List their
#   org codes, highest first.
# Answer looks like: 5 org codes in order, e.g. c("AAA", "BBB", ...).
# Gotcha from notes.md: "NHS trust vs other providers: a 3-character ODS code
#   starting with R or T (grepl("^[RT][A-Z0-9]{2}$", code))."
#
# Plan:
#   1. Keep Sep 2026 and only NHS trusts (use the pattern from notes.md).
#   2. Sort from most to fewest Type 1 attendances.
#   3. Keep the top 5 rows.
#   4. Take out the org codes.
#
# Tools you'll need:
#   grepl(pattern, column)  NEW: TRUE where the text matches the pattern.
#                           Works inside filter().
#   arrange()               NEW: sorts rows. Smallest first by default.
#   desc()                  NEW: inside arrange(), sorts biggest first.
#   head(n)                 NEW: keeps the first n rows.
#   pull()                  takes one column out. With several rows, you get a list.
#
# Fill in each .___ (there are 4 blanks).
# --------------------------------------------------------------------------

library(dplyr)
library(arrow)
source("eval/truth/key/check.R")

ae <- read_parquet("data/clean/ae_provider.parquet")

answer <- ae |>
  filter(period == as.Date("2026-09-01"),
         grepl(.___, org_code)) |>          # blank 1
  arrange(.___) |>                          # blank 2
  head(.___) |>                             # blank 3
  pull(.___)                                # blank 4

answer
check_answer("q15", answer)

# Hints ---------------------------------------------------------------------
# Hint 1: The pattern is in notes.md (and in this file's header). It's text,
#         so it needs quotes.
# Hint 2: Biggest first, on the Type 1 attendances column from the question.
# Hint 3: How many trusts does the question ask for?
# Hint 4: The column holding the codes you want to list.

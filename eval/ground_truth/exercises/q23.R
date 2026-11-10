# q23 ---------------------------------------------------------------------
# Question: What was England's all-types A&E 4-hour performance in December 2026?
# Answer looks like: a REFUSAL. The data can't answer this, so the correct
#   answer is refusal("<why>"), with a reason saying what the data does cover.
# Gotcha from notes.md: "Different months." Each table covers a fixed range.
#
# Plan:
#   1. Find the latest month in the A&E table.
#   2. Check whether December 2026 is in the table at all.
#   3. If it isn't, refuse, and say which months the data covers.
#
# Tools you'll need:
#   max()        the largest value. On a date column, the latest date.
#   any()        TRUE if at least one value is TRUE.
#   stopifnot()  stops with an error if its condition is FALSE. Here it proves
#                your claim: the file only reaches the refusal if the data
#                really lacks December 2026.
#   refusal()    NEW: refusal("reason") is the answer for a question the data
#                can't answer.
#
# Fill in each .___ (there are 3 blanks).
# --------------------------------------------------------------------------

library(dplyr)
library(arrow)
source("eval/ground_truth/exercises/check.R")

ae <- read_parquet("data/clean/ae_provider.parquet")

latest_month <- .___                                  # blank 1
latest_month

has_december_2026 <- any(ae$period == .___)           # blank 2
has_december_2026                                     # should be FALSE

stopifnot(!has_december_2026)                         # proof: Dec 2026 isn't in the data

answer <- refusal(.___)                               # blank 3

answer
check_answer("q23", answer)

# Hints ---------------------------------------------------------------------
# Hint 1: The latest value of the period column.
# Hint 2: December 2026, written as a date the same way as every other month.
# Hint 3: A sentence in quotes explaining why you can't answer: what month the
#         data ends at, and that December 2026 isn't in it.

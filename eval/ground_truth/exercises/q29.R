# q29 ---------------------------------------------------------------------
# Question: Compare each pair of consecutive RTT months like for like, counting
#   only providers with a C_999 row in both months. In how many of the 23
#   month-to-month changes did England's incomplete pathways fall?
# Answer looks like: a whole number (months). Must match exactly.
# Gotcha from notes.md: "Missing submissions... A month-on-month drop may be a
#   gap in submissions, not a real fall." Comparing raw national totals counts
#   missing trusts as falls, and returning trusts as rises.
#
# Plan:
#   1. Keep the C_999 rows and list the 24 months in order.
#   2. For each month after the first:
#        a. take that month and the month before,
#        b. find the providers in both,
#        c. total each month for just those providers,
#        d. if the later total is smaller, count one fall.
#   3. The answer is the number of falls.
#
# Tools you'll need:
#   for (i in 2:length(months)) { ... }  NEW: repeats the code inside { } once
#                for each i. months[i] is this month, months[i - 1] the one before.
#   intersect(a, b)  the values in both a and b (q19).
#   if (condition) x <- x + 1   adds one only when the condition is TRUE.
#   filter(), pull(), sum(), %in%
#
# Fill in each .___ (there are 4 blanks).
# --------------------------------------------------------------------------

library(dplyr)
library(arrow)
source("eval/ground_truth/exercises/check.R")

rtt <- read_parquet("data/clean/rtt_incomplete_provider.parquet")
c999 <- rtt |> filter(is_all_specialties_total)
months <- sort(unique(c999$period))

falls <- 0
for (i in 2:length(months)) {
  prev <- c999 |> filter(period == months[i - 1])
  curr <- c999 |> filter(period == months[i])

  in_both <- .___                                                    # blank 1
  prev_total <- .___                                                 # blank 2
  curr_total <- .___                                                 # blank 3

  if (.___) falls <- falls + 1                                       # blank 4
}

answer <- falls

answer
check_answer("q29", answer)

# Hints ---------------------------------------------------------------------
# Hint 1: intersect() the provider codes of prev and curr (pull them out first).
# Hint 2: Sum prev's total_incomplete, keeping only providers %in% in_both.
#         Plain sum(x[condition]) works as well as a pipeline.
# Hint 3: The same as blank 2, for curr.
# Hint 4: The condition for "this month is lower than the month before".

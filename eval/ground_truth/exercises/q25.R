# q25 ---------------------------------------------------------------------
# Question: How many patients in England spent more than 12 hours in A&E from
#   arrival in Sep 2026?
# Answer looks like: a REFUSAL, refusal("<why>").
# Gotcha from notes.md: "dta_wait_over_12hrs is measured from the decision to
#   admit, not from arrival. 12 hours from arrival is NOT in this data."
#
# Plan:
#   1. Find every A&E column about 12-hour waits.
#   2. Show they all measure from the decision to admit (their names start with "dta").
#   3. Refuse, and say what the data measures instead and where the
#      arrival-based figure is published.
#
# Tools you'll need:
#   grep(pattern, x, value = TRUE)   the values of x containing the pattern (see q24).
#   startsWith(x, prefix)            TRUE for each value of x that begins with prefix.
#   all()                            TRUE only if every value is TRUE.
#   stopifnot(), refusal()           see q23.
#
# Fill in each .___ (there are 3 blanks).
# --------------------------------------------------------------------------

library(dplyr)
library(arrow)
source("eval/ground_truth/exercises/check.R")

ae <- read_parquet("data/clean/ae_provider.parquet")

twelve_hour_columns <- grep(.___, names(ae), value = TRUE)          # blank 1
twelve_hour_columns

all_from_decision_to_admit <- all(startsWith(twelve_hour_columns, .___))   # blank 2
stopifnot(all_from_decision_to_admit)                     # proof: no arrival-based 12-hour column

answer <- refusal(.___)                                              # blank 3

answer
check_answer("q25", answer)

# Hints ---------------------------------------------------------------------
# Hint 1: Text that appears in the name of every 12-hour column.
# Hint 2: The three letters those column names start with.
# Hint 3: Say what the 12-hour column measures from, and where 12 hours from
#         arrival is published instead (see notes.md).

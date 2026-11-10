# q24 ---------------------------------------------------------------------
# Question: How many unique patients were waiting for consultant-led (RTT)
#   treatment in England at the end of Aug 2026?
# Answer looks like: a REFUSAL, refusal("<why>"), because the data can't
#   answer this as asked.
# Gotcha from notes.md: "Counts are pathways, not patients. One patient can
#   have several pathways."
#
# Plan:
#   1. Look at the RTT columns.
#   2. Show that none of them counts patients.
#   3. Refuse, and explain what the data counts instead.
#
# Tools you'll need:
#   names()        the column names of a table.
#   grep(pattern, x, value = TRUE, ignore.case = TRUE)
#                  the values of x that contain the pattern (any case).
#   length()       how many values there are.
#   stopifnot(), refusal()   see q23.
#
# Fill in each .___ (there are 2 blanks).
# --------------------------------------------------------------------------

library(dplyr)
library(arrow)
source("eval/ground_truth/exercises/check.R")

rtt <- read_parquet("data/clean/rtt_incomplete_provider.parquet")

names(rtt)                                                         # look for yourself

patient_columns <- grep(.___, names(rtt), value = TRUE, ignore.case = TRUE)   # blank 1
patient_columns                                                    # should be empty

stopifnot(length(patient_columns) == 0)                            # proof: no patient counts

answer <- refusal(.___)                                            # blank 2

answer
check_answer("q24", answer)

# Hints ---------------------------------------------------------------------
# Hint 1: The word you'd expect in the name of a column that counts patients.
# Hint 2: Say what the data counts instead of patients, and why that's different.

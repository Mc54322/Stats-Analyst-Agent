# q28 ---------------------------------------------------------------------
# Question: Counting only providers that have a C_999 row in every one of the
#   24 RTT months, what was the change in England's incomplete pathways from
#   Sep 2024 to Aug 2026? Give Aug 2026 minus Sep 2024.
# Answer looks like: one number (pathways).
# Gotchas from notes.md: "Missing submissions" and "More providers over time".
#   Restricting to providers present every month stops joiners, leavers and
#   gaps from looking like changes in the waiting list.
#
# Plan:
#   1. Keep the C_999 rows.
#   2. Find the providers with a row in all 24 months.
#   3. Total their pathways in Sep 2024, and again in Aug 2026.
#   4. Subtract: Aug 2026 minus Sep 2024.
#
# Tools you'll need:
#   count(col)  NEW: one row per value of col, with n = how many rows it had.
#   function(x) { ... }  NEW: write a small function so you don't repeat the
#               same pipeline. total_in() below is one; it's done for you.
#   filter(), pull(), %in%
#
# Fill in each .___ (there are 2 blanks).
# --------------------------------------------------------------------------

library(dplyr)
library(arrow)
source("eval/ground_truth/exercises/check.R")

rtt <- read_parquet("data/clean/rtt_incomplete_provider.parquet")
c999 <- rtt |> filter(is_all_specialties_total)

every_month <- c999 |>
  count(provider_org_code) |>
  filter(.___) |>                                     # blank 1
  pull(provider_org_code)

length(every_month)                                   # providers present all 24 months

total_in <- function(month) {
  c999 |>
    filter(period == as.Date(month), provider_org_code %in% every_month) |>
    summarise(total = sum(total_incomplete)) |>
    pull(total)
}

answer <- .___                                        # blank 2

answer
check_answer("q28", answer)

# Hints ---------------------------------------------------------------------
# Hint 1: A condition on n that means "present in all 24 months".
# Hint 2: Call total_in() twice, once per month (as "YYYY-MM-DD" text), and subtract.

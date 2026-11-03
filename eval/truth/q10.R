# q10 ---------------------------------------------------------------------
# Question: In Aug 2026, how many RTT pathways in England had waited more than
#   52 weeks but not more than 65 weeks? Use the C_999 rows for all providers.
# Answer looks like: one number (pathways).
# Gotcha from notes.md (TRAP): "over_*_weeks columns are cumulative."
#   over_52_weeks already includes everyone in over_65_weeks. To get a band
#   like 52-65 weeks, subtract one from the other.
#
# Plan:
#   1. Keep Aug 2026 and the C_999 rows.
#   2. Add up over_52_weeks and over_65_weeks across all providers.
#   3. The band is the 52-week total minus the 65-week total.
#
# Tools you'll need:
#   filter()     keeps rows that match. Two conditions, separated by a comma.
#   summarise()  squashes rows into one row of results.
#   mutate()     adds a column calculated from other columns.
#   pull()       takes one column out as a plain value.
#
# Fill in each .___ (there are 4 blanks).
# --------------------------------------------------------------------------

library(dplyr)
library(arrow)
source("eval/truth/key/check.R")

rtt <- read_parquet("data/clean/rtt_incomplete_provider.parquet")

answer <- rtt |>
  filter(.___, .___) |>                       # blanks 1 and 2
  summarise(over_52 = sum(over_52_weeks),
            over_65 = sum(.___)) |>          # blank 3
  mutate(band = .___) |>                     # blank 4
  pull(band)

answer
check_answer("q10", answer)

# Hints ---------------------------------------------------------------------
# Hint 1: The month condition. You've written it several times now.
# Hint 2: The condition that keeps only the total rows (see q07).
# Hint 3: The column for waits over 65 weeks.
# Hint 4: Use the two names made in summarise(). Bigger one first.

# RTT incomplete pathways by provider: the last 24 months.
#
# Source:  https://www.england.nhs.uk/statistics/statistical-work-areas/rtt-waiting-times/
# Input:   the monthly "Full CSV data file" ZIP. It holds every RTT part, split
#          by provider x commissioner x treatment function x one-week wait band.
# Output:  data/clean/rtt_incomplete_provider.parquet with one row per
#          month x provider x treatment function.
#
# Run from the repo root:  Rscript data/ingest/rtt_incomplete_provider.R

source("R/ingest_helpers.R")
check_repo_root()
suppressPackageStartupMessages({
  library(readr)
  library(tidyr)
  library(purrr)
  library(arrow)
})

N_MONTHS <- 24
LANDING_URL <- "https://www.england.nhs.uk/statistics/statistical-work-areas/rtt-waiting-times/"
RAW_DIR <- "data/raw/rtt"
OUT_PATH <- "data/clean/rtt_incomplete_provider.parquet"

# The identifier and name columns are text and every other column is a count.
# Reading the counts as doubles means that a non-numeric value is reported as
# a parse problem instead of being quietly coerced.
RTT_TEXT_COLS <- c(
  "Period", "Provider Parent Org Code", "Provider Parent Name",
  "Provider Org Code", "Provider Org Name", "Commissioner Parent Org Code",
  "Commissioner Parent Name", "Commissioner Org Code", "Commissioner Org Name",
  "RTT Part Type", "RTT Part Description", "Treatment Function Code",
  "Treatment Function Name"
)
rtt_col_types <- do.call(
  cols,
  c(list(.default = col_double()), setNames(rep(list(col_character()), length(RTT_TEXT_COLS)), RTT_TEXT_COLS))
)

# ---- 1. Find the monthly files ----------------------------------------------
# Each financial year has its own page. 24 months span at most 3 financial
# years. We read the newest 4 pages because a new year's page can exist before
# it has any files on it.
cat("Finding RTT financial-year pages\n")
year_pages <- financial_year_pages(LANDING_URL, "rtt-waiting-times/rtt-data-(\\d{4}-\\d{2})/?$", n = 4)
print(year_pages)

links <- map(year_pages$url, scrape_links) |>
  list_rbind() |>
  # Only the full CSV extract. The XLSX files on the same pages are
  # pre-summarised views of the same data.
  filter(str_detect(url, "Full-CSV-data-file-[A-Za-z]{3}\\d{2}-ZIP.*\\.zip$")) |>
  distinct(url, .keep_all = TRUE) |>
  mutate(
    mon_yy = str_match(url, "Full-CSV-data-file-([A-Za-z]{3})(\\d{2})-ZIP"),
    month = parse_mon_yy(mon_yy[, 2], mon_yy[, 3])
  ) |>
  select(-mon_yy)
if (anyNA(links$month)) {
  print(filter(links, is.na(month)))
  stop("Could not read the month from some RTT filenames (listed above).")
}
files <- latest_months(links, N_MONTHS)
cat(sprintf(
  "Using %d months: %s to %s\n", nrow(files),
  format(min(files$month), "%b %Y"), format(max(files$month), "%b %Y")
))

# ---- 2. Download -----------------------------------------------------------
files$path <- map_chr(files$url, download_once, dest_dir = RAW_DIR)

# ---- 3. Clean each month ----------------------------------------------------
# Each extract has about 180k rows and 120 columns, so each file is reduced to
# provider level before moving on. That keeps memory use low.

process_month <- function(path, expected_month) {
  cat(sprintf("\n%s  (%s)\n", basename(path), format(expected_month, "%b %Y")))

  raw <- read_csv(path, col_types = rtt_col_types, na = "", progress = FALSE)
  stop_on_parse_problems(raw, path)
  log_step(raw, "read full extract (all RTT parts)")

  # snake_case names, e.g. "Gt 00 To 01 Weeks SUM 1" -> gt_00_to_01_weeks_sum_1.
  raw <- janitor::clean_names(raw)

  # The extract has one column per one-week band, from >0-1 weeks up to
  # >103-104 weeks, plus a final >104 weeks band: 105 in all. If that changes,
  # the threshold sums below would be wrong, so stop.
  band_cols <- str_subset(names(raw), "^gt_\\d+")
  if (length(band_cols) != 105) {
    stop(sprintf("Expected 105 weekly wait-band columns, found %d.", length(band_cols)))
  }
  band_lower <- as.integer(str_match(band_cols, "^gt_(\\d+)")[, 2])

  # SCOPE: keep only Part_2, "Incomplete Pathways" (patients still waiting).
  #  - Part_1A/1B are completed pathways and Part_3 is new clock starts. They
  #    measure different things.
  #  - Part_2A ("Incomplete Pathways with DTA") is a SUBSET of Part_2.
  #    Keeping it as well would double count those patients.
  # These rows are left out on purpose, not lost. Their counts are printed here.
  cat("  rows by RTT part:\n")
  part_counts <- count(raw, rtt_part_type, rtt_part_description)
  cat(sprintf(
    "    %-8s %-45s %10s %s\n", part_counts$rtt_part_type, part_counts$rtt_part_description,
    fmt_n(part_counts$n), ifelse(part_counts$rtt_part_type == "Part_2", "<- kept", "")
  ), sep = "")
  inc <- filter(raw, rtt_part_type == "Part_2")
  log_step(inc, "keep Part_2 incomplete pathways", raw)
  rm(raw)

  # BLANK CELLS: a blank count means zero patients in that band. The evidence
  # is that, with blanks read as 0, the bands plus "unknown clock start" add up
  # to the published "Total All" on every row (checked below). Rows are kept,
  # and only cell values change.
  count_cols <- c(band_cols, "patients_with_unknown_clock_start_date", "total_all")
  n_blank <- sum(is.na(inc[count_cols]))
  inc_filled <- mutate(inc, across(all_of(count_cols), \(x) coalesce(x, 0)))
  cat(sprintf("  %-58s %12s cells\n", "blank count cells set to 0", fmt_n(n_blank)))
  log_step(inc_filled, "after filling blanks", inc)
  inc <- inc_filled
  rm(inc_filled)

  # "Total" is left blank for Part_2 in the extract ("Total All" is the
  # populated total). We drop the column and rebuild the known-clock-start
  # total from the bands. If NHS England ever starts filling it in, print a
  # note so the decision can be checked again.
  if (any(!is.na(inc$total))) {
    cat("  NOTE: 'Total' is populated for some Part_2 rows; it is still dropped in favour of the band sum.\n")
  }

  # CONSISTENCY CHECK: the band sum plus unknown clock start should equal
  # Total All. Rows that do not match are counted and KEPT, with Total All as
  # published.
  band_sum <- rowSums(inc[band_cols])
  n_mismatch <- sum(abs(band_sum + inc$patients_with_unknown_clock_start_date - inc$total_all) > 0.5)
  cat(sprintf("  %-58s %12s rows\n", "rows where bands + unknown != Total All (kept)", fmt_n(n_mismatch)))

  # MEASURES: each band "gt_A_to_B" counts waits of more than A and up to B
  # weeks, and "gt_104" counts more than 104 weeks. So:
  #   within 18 weeks = bands with A < 18 (that is, up to 18 weeks)
  #   over 52 weeks   = bands with A >= 52 (more than 52 weeks), and so on.
  # These follow NHS England's published 18/52/65/78/104-week measures.
  inc <- inc |>
    mutate(
      known_clock_start = band_sum,
      within_18_weeks = rowSums(pick(all_of(band_cols[band_lower < 18]))),
      over_52_weeks   = rowSums(pick(all_of(band_cols[band_lower >= 52]))),
      over_65_weeks   = rowSums(pick(all_of(band_cols[band_lower >= 65]))),
      over_78_weeks   = rowSums(pick(all_of(band_cols[band_lower >= 78]))),
      over_104_weeks  = rowSums(pick(all_of(band_cols[band_lower >= 104])))
    ) |>
    select(-all_of(band_cols), -total)

  # AGGREGATE: add up across commissioners to get provider level. This merges
  # rows; it does not remove any patients. The check below confirms that the
  # patient total is unchanged.
  measure_cols <- c(
    "total_all", "patients_with_unknown_clock_start_date", "known_clock_start",
    "within_18_weeks", "over_52_weeks", "over_65_weeks", "over_78_weeks", "over_104_weeks"
  )
  prov <- inc |>
    group_by(
      period, provider_parent_org_code, provider_parent_name,
      provider_org_code, provider_org_name,
      treatment_function_code, treatment_function_name
    ) |>
    summarise(across(all_of(measure_cols), sum), n_commissioner_rows = n(), .groups = "drop")
  log_step(prov, "sum across commissioners -> provider x treatment function", inc)
  if (abs(sum(prov$total_all) - sum(inc$total_all)) > 0.5) {
    stop("Patient total changed when aggregating to provider level.")
  }

  # The grouping uses names as well as codes. If a provider's name or parent
  # differed between commissioner rows, that provider would be split into two
  # rows. Stop if any code appears more than once.
  dup_keys <- count(prov, period, provider_org_code, treatment_function_code) |> filter(n > 1)
  if (nrow(dup_keys) > 0) {
    print(dup_keys)
    stop("Provider codes with more than one name or parent in the same month (listed above).")
  }

  # PERIOD: "RTT-August-2026" becomes 2026-08-01, the first day of the
  # reporting month. Waiting lists are a snapshot taken at month end.
  prov <- mutate(prov, period = parse_period_month(period))
  if (anyNA(prov$period) || any(prov$period != expected_month)) {
    stop(sprintf("Period inside %s does not match the month in its filename.", basename(path)))
  }

  prov
}

monthly <- map2(files$path, files$month, process_month)

# ---- 4. Combine and finish --------------------------------------------------
cat("\nCombining months\n")
rtt <- list_rbind(monthly)
log_step(rtt, sprintf("bind %d months", length(monthly)), sum(map_int(monthly, nrow)))

rtt <- rtt |>
  rename(
    total_incomplete = total_all,
    unknown_clock_start = patients_with_unknown_clock_start_date
  ) |>
  mutate(
    over_18_weeks = known_clock_start - within_18_weeks,
    # NHS England's 18-week measure: the share of patients WITH a known clock
    # start who have waited up to 18 weeks. Unknown clock starts are left out
    # of both the top and bottom of the fraction. It is NA when no patient has
    # a known clock start, rather than dividing by zero.
    pct_within_18_weeks = if_else(known_clock_start > 0, within_18_weeks / known_clock_start, NA_real_),
    # C_999 "Total" is the provider's all-specialty total and is published
    # beside the individual specialties. We keep it because it is the figure
    # most questions need, and flag it so the specialties are never summed
    # together with it (that would double the count).
    is_all_specialties_total = treatment_function_code == "C_999"
  ) |>
  relocate(over_18_weeks, .after = within_18_weeks) |>
  relocate(is_all_specialties_total, .after = treatment_function_name) |>
  arrange(period, provider_org_code, treatment_function_code)
log_step(rtt, "add derived measures")

# CHECK: for each provider and month, C_999 should equal the sum of the
# specialty rows. Mismatches are printed and kept as published.
tf_check <- rtt |>
  group_by(period, provider_org_code) |>
  summarise(
    c999 = sum(total_incomplete[is_all_specialties_total]),
    specialties = sum(total_incomplete[!is_all_specialties_total]),
    .groups = "drop"
  ) |>
  filter(abs(c999 - specialties) > 0.5)
cat(sprintf("  %-58s %12s\n", "provider-months where C_999 != sum of specialties", fmt_n(nrow(tf_check))))
if (nrow(tf_check) > 0) print(head(tf_check, 10))

dir.create(dirname(OUT_PATH), recursive = TRUE, showWarnings = FALSE)
write_parquet(rtt, OUT_PATH)
cat(sprintf(
  "\nWrote %s rows to %s\n  %s to %s, %s providers\n",
  fmt_n(nrow(rtt)), OUT_PATH,
  format(min(rtt$period), "%b %Y"), format(max(rtt$period), "%b %Y"),
  fmt_n(n_distinct(rtt$provider_org_code))
))

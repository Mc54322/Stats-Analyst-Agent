# A&E attendances, emergency admissions and 4-hour performance by provider:
# the last 24 months.
#
# Source:  https://www.england.nhs.uk/statistics/statistical-work-areas/ae-waiting-times-and-activity/
# Input:   the "Monthly A&E <Month> <Year>" CSV, with one row per provider
#          plus a national TOTAL row.
# Output:  data/clean/ae_provider.parquet with one row per month x provider.
# Definitions: see "A&E Attendances and Emergency Admissions Definitions",
#          linked from the source page.
#
# Run from the repo root:  Rscript data/ingest/ae_provider.R

source("R/ingest_helpers.R")
check_repo_root()
suppressPackageStartupMessages({
  library(readr)
  library(tidyr)
  library(purrr)
  library(arrow)
})

N_MONTHS <- 24
LANDING_URL <- "https://www.england.nhs.uk/statistics/statistical-work-areas/ae-waiting-times-and-activity/"
RAW_DIR <- "data/raw/ae"
OUT_PATH <- "data/clean/ae_provider.parquet"

# The published column names mapped to short snake_case names. Renaming
# through this explicit map (rather than janitor) means a renamed or missing
# source column stops the script instead of producing an odd name.
AE_COLS <- c(
  period                     = "Period",
  org_code                   = "Org Code",
  parent_org                 = "Parent Org",
  org_name                   = "Org name",
  attendances_type1          = "A&E attendances Type 1",
  attendances_type2          = "A&E attendances Type 2",
  attendances_other          = "A&E attendances Other A&E Department",
  attendances_booked_type1   = "A&E attendances Booked Appointments Type 1",
  attendances_booked_type2   = "A&E attendances Booked Appointments Type 2",
  attendances_booked_other   = "A&E attendances Booked Appointments Other Department",
  over_4hrs_type1            = "Attendances over 4hrs Type 1",
  over_4hrs_type2            = "Attendances over 4hrs Type 2",
  over_4hrs_other            = "Attendances over 4hrs Other Department",
  over_4hrs_booked_type1     = "Attendances over 4hrs Booked Appointments Type 1",
  over_4hrs_booked_type2     = "Attendances over 4hrs Booked Appointments Type 2",
  over_4hrs_booked_other     = "Attendances over 4hrs Booked Appointments Other Department",
  dta_wait_4_to_12hrs        = "Patients who have waited 4-12 hs from DTA to admission",
  dta_wait_over_12hrs        = "Patients who have waited 12+ hrs from DTA to admission",
  emergency_admissions_type1 = "Emergency admissions via A&E - Type 1",
  emergency_admissions_type2 = "Emergency admissions via A&E - Type 2",
  emergency_admissions_other = "Emergency admissions via A&E - Other A&E department",
  other_emergency_admissions = "Other emergency admissions"
)
TEXT_COLS <- c("period", "org_code", "parent_org", "org_name")
COUNT_COLS <- setdiff(names(AE_COLS), TEXT_COLS)

ae_col_types <- do.call(
  cols,
  c(list(.default = col_double()), setNames(rep(list(col_character()), 4), AE_COLS[TEXT_COLS]))
)

# ---- 1. Find the monthly files ----------------------------------------------
# One page per financial year. We read the newest 4 because a new year's page
# can exist before it has any files on it.
cat("Finding A&E financial-year pages\n")
year_pages <- financial_year_pages(
  LANDING_URL, "ae-attendances-and-emergency-admissions-(\\d{4}-\\d{2})/?$", n = 4
)
print(year_pages)

# The CSV filenames follow no pattern over time ("Monthly-AE-October-2024-
# revised.csv", "April-2026-CSV-QD21vf.csv", "Monthly-AE-Nov-25-CSV-revised.csv").
# The link text has been stable, though: "Monthly A&E <Month> <Year> (...)".
# So we pick out and date files by link text, and later check that date
# against the Period column inside each file.
month_pattern <- paste0("^Monthly A&E (", paste(month.name, collapse = "|"), ") (\\d{4})")
links <- map(year_pages$url, scrape_links) |>
  list_rbind() |>
  filter(str_detect(url, "\\.csv$"), str_detect(text, regex("^Monthly A&E", ignore_case = TRUE))) |>
  distinct(url, .keep_all = TRUE) |>
  mutate(
    m = str_match(text, regex(month_pattern, ignore_case = TRUE)),
    month = lubridate::make_date(as.integer(m[, 3]), match(tolower(m[, 2]), tolower(month.name)), 1L)
  ) |>
  select(-m)
if (anyNA(links$month)) {
  print(filter(links, is.na(month)))
  stop("Could not read the month from some A&E link texts (listed above).")
}
files <- latest_months(links, N_MONTHS)
cat(sprintf(
  "Using %d months: %s to %s\n", nrow(files),
  format(min(files$month), "%b %Y"), format(max(files$month), "%b %Y")
))

# ---- 2. Download -----------------------------------------------------------
files$path <- map_chr(files$url, download_once, dest_dir = RAW_DIR)

# ---- 3. Read ----------------------------------------------------------------
read_month <- function(path, expected_month) {
  df <- read_csv(path, col_types = ae_col_types, na = "", progress = FALSE)
  stop_on_parse_problems(df, path)
  missing <- setdiff(AE_COLS, names(df))
  extra <- setdiff(names(df), AE_COLS)
  if (length(missing) > 0) stop(sprintf("%s is missing columns: %s", basename(path), toString(missing)))
  # Extra columns are reported rather than dropped without a word. They would
  # need a decision about whether they belong in the tidy output.
  if (length(extra) > 0) cat(sprintf("  NOTE: %s has extra columns, not kept: %s\n", basename(path), toString(extra)))
  log_step(df, sprintf("read %s (%s)", basename(path), format(expected_month, "%b %Y")))
  selected <- select(df, all_of(AE_COLS))
  log_step(selected, "  select and rename columns", df)
  df <- selected
  mutate(df, expected_month = expected_month, source_file = basename(path))
}

cat("\nReading files\n")
monthly <- map2(files$path, files$month, read_month)
ae_raw <- list_rbind(monthly)
log_step(ae_raw, sprintf("bind %d months", length(monthly)), sum(map_int(monthly, nrow)))

# ---- 4. Clean ---------------------------------------------------------------
cat("\nCleaning\n")

# NATIONAL TOTAL ROW: every file ends with an England total row. It is not a
# provider, so it is taken out of the provider table. Before discarding it, we
# check that the provider rows add up to it for every count column.
# Its label varies from file to file: "TOTAL" in most months, "Total" in Jun
# and Jul 2026, "TOTAL " with a trailing space in May 2026. In Feb 2026 the
# Period column holds the month instead of "TOTAL". So we match org_code,
# ignoring case and whitespace.
is_total <- toupper(str_squish(coalesce(ae_raw$org_code, ""))) == "TOTAL"
totals <- ae_raw[is_total, ]
ae <- ae_raw[!is_total, ]
log_step(ae, "remove national TOTAL rows (1 per month)", ae_raw)
if (nrow(totals) != length(monthly)) {
  stop(sprintf("Expected 1 TOTAL row per file, found %d over %d files.", nrow(totals), length(monthly)))
}
total_check <- ae |>
  group_by(source_file) |>
  summarise(across(all_of(COUNT_COLS), \(x) sum(x, na.rm = TRUE)), .groups = "drop") |>
  pivot_longer(-source_file, names_to = "measure", values_to = "provider_sum") |>
  inner_join(
    totals |>
      select(source_file, all_of(COUNT_COLS)) |>
      pivot_longer(-source_file, names_to = "measure", values_to = "published_total"),
    by = c("source_file", "measure")
  ) |>
  filter(abs(provider_sum - published_total) > 0.5)
cat(sprintf("  %-58s %12s\n", "file x measure where providers != TOTAL row", fmt_n(nrow(total_check))))
if (nrow(total_check) > 0) print(head(total_check, 20))

# WHITESPACE: names are published with trailing spaces
# ("NHS ENGLAND SOUTH EAST "). read_csv already trims leading and trailing
# spaces (trim_ws = TRUE), so this step mainly collapses repeated spaces
# inside names. It may well report 0. Only values change here.
before <- ae
ae <- mutate(ae, across(all_of(c("org_code", "parent_org", "org_name")), str_squish))
n_changed <- sum(before$parent_org != ae$parent_org, na.rm = TRUE) +
  sum(before$org_name != ae$org_name, na.rm = TRUE) +
  sum(before$org_code != ae$org_code, na.rm = TRUE)
log_step(ae, sprintf("trim whitespace in %s text cells", fmt_n(n_changed)), before)
rm(before)

# PERIOD: "MSitAE-SEPTEMBER-2026" becomes 2026-09-01, the first day of the
# activity month. It must match the month in the link text.
n_before <- nrow(ae)
ae <- mutate(ae, period = parse_period_month(period))
bad_period <- filter(ae, is.na(period) | period != expected_month)
if (nrow(bad_period) > 0) {
  print(distinct(bad_period, source_file, expected_month, period))
  stop("Period inside some files does not match their link text (listed above).")
}
ae <- select(ae, -expected_month)
log_step(ae, "parse period to month-start date", n_before)

# MISSING COUNTS: the files use explicit zeros, so a blank count is unexpected.
# Blanks are kept as NA, not set to 0, because we cannot tell a true zero from
# an unreported value. Derived totals for those rows are then NA as well.
na_counts <- colSums(is.na(ae[COUNT_COLS]))
cat(sprintf("  %-58s %12s cells\n", "blank count cells (kept as NA)", fmt_n(sum(na_counts))))
if (sum(na_counts) > 0) print(na_counts[na_counts > 0])

# KEY: there should be exactly one row per provider per month.
dup_keys <- count(ae, period, org_code) |> filter(n > 1)
if (nrow(dup_keys) > 0) {
  print(dup_keys)
  stop("Duplicate provider rows within a month (listed above).")
}

# ---- 5. Derived measures ----------------------------------------------------
# DEPARTMENT TYPES: Type 1 is a consultant-led 24-hour major A&E. Type 2 is a
# single-specialty A&E (for example eye or dental). "Other" covers urgent
# treatment centres, walk-in centres and minor injury units. "Booked
# appointments" are booked-in attendances at those same department types.
#
# 4-HOUR MEASURE: NHS England's headline figure is the percentage of ALL
# attendances (every type, booked appointments included) spent in A&E for 4
# hours or less, from arrival to admission, transfer or discharge. The Type 1
# figure uses Type 1 attendances plus Type 1 booked appointments. Both are NA
# when there were no attendances, rather than dividing by zero.
n_before <- nrow(ae)
ae <- ae |>
  mutate(
    attendances_total = attendances_type1 + attendances_type2 + attendances_other +
      attendances_booked_type1 + attendances_booked_type2 + attendances_booked_other,
    over_4hrs_total = over_4hrs_type1 + over_4hrs_type2 + over_4hrs_other +
      over_4hrs_booked_type1 + over_4hrs_booked_type2 + over_4hrs_booked_other,
    pct_within_4hrs = if_else(attendances_total > 0, 1 - over_4hrs_total / attendances_total, NA_real_),
    attendances_type1_all = attendances_type1 + attendances_booked_type1,
    over_4hrs_type1_all = over_4hrs_type1 + over_4hrs_booked_type1,
    pct_within_4hrs_type1 = if_else(attendances_type1_all > 0, 1 - over_4hrs_type1_all / attendances_type1_all, NA_real_),
    emergency_admissions_via_ae = emergency_admissions_type1 + emergency_admissions_type2 + emergency_admissions_other,
    emergency_admissions_total = emergency_admissions_via_ae + other_emergency_admissions,
    # Providers with no A&E attendances at all (for example some community
    # providers that report only "other emergency admissions") are KEPT. They
    # are flagged so A&E performance questions can exclude them on purpose.
    has_ae_activity = coalesce(attendances_total, 0) > 0
  )
log_step(ae, "add derived totals and 4-hour percentages", n_before)

# CHECK: attendances over 4 hours should never exceed attendances. Rows that
# do are printed and kept as published.
impossible <- filter(ae, over_4hrs_total > attendances_total)
cat(sprintf("  %-58s %12s rows\n", "rows with over-4hr > attendances (kept)", fmt_n(nrow(impossible))))
if (nrow(impossible) > 0) print(select(impossible, period, org_code, org_name, attendances_total, over_4hrs_total))
cat(sprintf("  %-58s %12s rows\n", "rows with no A&E attendances (kept, flagged)", fmt_n(sum(!ae$has_ae_activity))))

ae <- ae |>
  relocate(source_file, .after = last_col()) |>
  arrange(period, org_code)

dir.create(dirname(OUT_PATH), recursive = TRUE, showWarnings = FALSE)
write_parquet(ae, OUT_PATH)
cat(sprintf(
  "\nWrote %s rows to %s\n  %s to %s, %s providers\n",
  fmt_n(nrow(ae)), OUT_PATH,
  format(min(ae$period), "%b %Y"), format(max(ae$period), "%b %Y"),
  fmt_n(n_distinct(ae$org_code))
))

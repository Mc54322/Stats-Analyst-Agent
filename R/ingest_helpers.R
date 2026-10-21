# Shared helpers for the scripts in data/ingest/.
# Source from the repo root: source("R/ingest_helpers.R")

suppressPackageStartupMessages({
  library(dplyr)
  library(stringr)
  library(rvest)
})

# Downloads of 80MB+ files can exceed R's default 60s timeout.
options(timeout = max(600, getOption("timeout")))

fmt_n <- function(n) format(n, big.mark = ",", scientific = FALSE)

# Print a row count for a pipeline step. Pass `before` (a data frame or a
# number) to also print the change, so no step can drop rows unnoticed.
log_step <- function(after, step, before = NULL) {
  n_after <- if (is.numeric(after)) after else nrow(after)
  if (is.null(before)) {
    cat(sprintf("  %-58s %12s rows\n", step, fmt_n(n_after)))
  } else {
    n_before <- if (is.numeric(before)) before else nrow(before)
    cat(sprintf(
      "  %-58s %12s -> %12s rows (%s)\n",
      step, fmt_n(n_before), fmt_n(n_after),
      if (n_after == n_before) "no change" else sprintf("%+d", n_after - n_before)
    ))
  }
  invisible(after)
}

check_repo_root <- function() {
  if (!file.exists("R/ingest_helpers.R")) {
    stop("Run this script from the repository root, e.g. `Rscript data/ingest/<script>.R`.")
  }
}

# All <a> links on a page as a tibble of absolute URLs and visible text.
scrape_links <- function(page_url) {
  anchors <- read_html(page_url) |> html_elements("a[href]")
  tibble(
    url = xml2::url_absolute(html_attr(anchors, "href"), page_url),
    text = str_squish(html_text2(anchors))
  )
}

# Financial-year pages ("2025-26") linked from a landing page, newest first.
# The same year is often linked twice (with and without a trailing slash, or
# under an old URL scheme), so keep one URL per year.
financial_year_pages <- function(landing_url, url_pattern, n) {
  scrape_links(landing_url) |>
    mutate(year = str_match(url, url_pattern)[, 2]) |>
    filter(!is.na(year)) |>
    distinct(year, .keep_all = TRUE) |>
    arrange(desc(year)) |>
    slice_head(n = n) |>
    select(year, url)
}

# Pick one link per month and keep the latest `n_months`. When a month is
# linked more than once (an original and a revised file), keep the one in the
# newest upload folder (/uploads/sites/2/YYYY/MM/), since NHS England uploads
# revisions later. Every discarded duplicate is printed.
latest_months <- function(links, n_months) {
  links <- links |>
    mutate(upload_folder = str_match(url, "/uploads/sites/\\d+/(\\d{4}/\\d{2})/")[, 2]) |>
    arrange(desc(month), desc(upload_folder))
  dupes <- links |> group_by(month) |> filter(n() > 1) |> slice(-1) |> ungroup()
  if (nrow(dupes) > 0) {
    cat("  Duplicate links for the same month; keeping the newest upload. Discarded:\n")
    cat(paste0("    ", format(dupes$month, "%b %Y"), "  ", dupes$url, "\n"), sep = "")
  }
  chosen <- links |> distinct(month, .keep_all = TRUE) |> slice_head(n = n_months)
  if (nrow(chosen) < n_months) {
    stop(sprintf(
      "Found only %d months of links (wanted %d). The page layout may have changed.",
      nrow(chosen), n_months
    ))
  }
  arrange(chosen, month)
}

# Download into dest_dir unless the file is already there. NHS England gives
# each revision a new filename, so a revised file is downloaded as a new file
# rather than silently overwriting the old one.
download_once <- function(url, dest_dir) {
  dir.create(dest_dir, recursive = TRUE, showWarnings = FALSE)
  dest <- file.path(dest_dir, basename(url))
  if (file.exists(dest) && file.size(dest) > 0) {
    cat("  cached     ", basename(dest), "\n")
  } else {
    cat("  downloading", basename(dest), "\n")
    tmp <- paste0(dest, ".part")
    utils::download.file(url, tmp, mode = "wb", quiet = TRUE)
    file.rename(tmp, dest)
  }
  dest
}

# "RTT-August-2026" / "MSitAE-SEPTEMBER-2026" -> first day of that month.
# Matched against month.name rather than parsed with %B, which depends on the
# system locale. Unrecognised values become NA, and callers check for them.
parse_period_month <- function(x) {
  m <- str_match(x, "([A-Za-z]+)-(\\d{4})\\s*$")
  lubridate::make_date(as.integer(m[, 3]), match(tolower(m[, 2]), tolower(month.name)), 1L)
}

# "Aug24" -> 2024-08-01
parse_mon_yy <- function(mon, yy) {
  lubridate::make_date(2000L + as.integer(yy), match(tolower(mon), tolower(month.abb)), 1L)
}

# Stop if readr reported parse problems. A value that fails to parse becomes
# NA, which would otherwise look like missing data.
stop_on_parse_problems <- function(df, file) {
  probs <- readr::problems(df)
  if (nrow(probs) > 0) {
    print(head(probs, 20))
    stop(sprintf("%d parse problems in %s", nrow(probs), basename(file)))
  }
  invisible(df)
}

# Compute the expected answer for every question in eval/questions.yaml.
#
# Reads the clean parquet files and writes eval/ground_truth/answers.json.
# Rerun after refreshing the data, then review the diff of answers.json:
# NHS England revises past months, so answers can change.
#
# Run from the repo root:  Rscript eval/ground_truth/compute_answers.R
#
# Conventions (see eval/questions.yaml and data/notes.md):
#   - RTT provider and national totals use only the C_999 rows.
#   - Percentages are ratios of sums, expressed as percent (65.2 = 65.2%).
#   - "NHS trust" = a 3-character ODS code starting with R or T.
#   - Questions the data can't answer expect a refusal: refusal_key() records
#     the keywords a reason must mention, after proving the data lacks the answer.

suppressPackageStartupMessages({
  library(dplyr)
  library(arrow)
})

RTT_PATH <- "data/clean/rtt_incomplete_provider.parquet"
AE_PATH <- "data/clean/ae_provider.parquet"
QUESTIONS_PATH <- "eval/questions.yaml"
OUT_PATH <- "eval/ground_truth/answers.json"
DATA_AS_OF <- "2026-10-21"

rtt <- read_parquet(RTT_PATH)
ae <- read_parquet(AE_PATH)

month <- function(x) as.Date(paste0(x, "-01"))
is_nhs_trust <- function(code) grepl("^[RT][A-Z0-9]{2}$", code)
pct_of <- function(num, den) 100 * sum(num) / sum(den)

c999 <- filter(rtt, is_all_specialties_total)
c999_month <- function(m) filter(c999, period == month(m))
ae_month <- function(m) filter(ae, period == month(m))

# Stops if a ranking has a tie at the cut-off, which would make the answer
# ambiguous (the question would need rewording).
top_n_strict <- function(df, value, n, code_col, decreasing = TRUE) {
  df <- df[order(df[[value]], decreasing = decreasing), ]
  if (nrow(df) > n && df[[value]][n] == df[[value]][n + 1]) {
    stop("Tie at position ", n, " for ", value, "; the ranking question is ambiguous.")
  }
  head(df[[code_col]], n)
}

# Expected answer for a question the data can't answer. `proof` must be TRUE,
# i.e. the data really lacks what the question needs; `keywords` are terms a
# refusal's reason must mention to explain why (any one is enough).
refusal_key <- function(proof, keywords) {
  if (!isTRUE(proof)) stop("Refusal proof failed: the data may be able to answer this question.")
  list(refusal = TRUE, keywords = keywords)
}

# Total incomplete pathways for a set of providers in one month (C_999 rows).
pathways_of <- function(codes, m) sum(c999_month(m) |> filter(provider_org_code %in% codes) |> pull(total_incomplete))

# Providers with a C_999 row in every month of the RTT table.
providers_every_month <- c999 |>
  count(provider_org_code) |>
  filter(n == n_distinct(c999$period)) |>
  pull(provider_org_code)

answers <- list(
  # q01: attendances_total for RTH, Sep 2026
  q01 = ae_month("2026-09") |> filter(org_code == "RTH") |> pull(attendances_total),

  # q02: incomplete pathways for RTH, C_999 row, Aug 2026
  q02 = c999_month("2026-08") |> filter(provider_org_code == "RTH") |> pull(total_incomplete),

  # q03: does RHQ have any RTT rows in Aug 2026?
  q03 = nrow(filter(rtt, provider_org_code == "RHQ", period == month("2026-08"))) > 0,

  # q04: providers with no A&E attendances, Sep 2026
  q04 = sum(!ae_month("2026-09")$has_ae_activity),

  # q05: national over-12-hour decision-to-admit waits, Sep 2026
  q05 = sum(ae_month("2026-09")$dta_wait_over_12hrs),

  # q06: distinct C_999 providers, Aug 2026 minus Sep 2024
  q06 = n_distinct(c999_month("2026-08")$provider_org_code) -
    n_distinct(c999_month("2024-09")$provider_org_code),

  # q07: England incomplete pathways, Aug 2026 (C_999 rows only)
  q07 = sum(c999_month("2026-08")$total_incomplete),

  # q08: all-types 4-hour performance, Sep 2026
  q08 = with(ae_month("2026-09"), 100 - pct_of(over_4hrs_total, attendances_total)),

  # q09: all-types minus Type 1 4-hour performance, Sep 2026 (percentage points)
  q09 = with(ae_month("2026-09"),
             (100 - pct_of(over_4hrs_total, attendances_total)) -
               (100 - pct_of(over_4hrs_type1_all, attendances_type1_all))),

  # q10: pathways waiting >52 and <=65 weeks, Aug 2026
  q10 = with(c999_month("2026-08"), sum(over_52_weeks) - sum(over_65_weeks)),

  # q11: national attendances, Sep 2026 minus Oct 2024
  q11 = sum(ae_month("2026-09")$attendances_total) - sum(ae_month("2024-10")$attendances_total),

  # q12: national >52-week waits, Aug 2026 minus Sep 2024
  q12 = sum(c999_month("2026-08")$over_52_weeks) - sum(c999_month("2024-09")$over_52_weeks),

  # q13: % within 18 weeks (known clock start), Aug 2026
  q13 = with(c999_month("2026-08"), pct_of(within_18_weeks, known_clock_start)),

  # q14: providers with more than one parent ICB code across all months
  q14 = c999 |>
    group_by(provider_org_code) |>
    summarise(n_parents = n_distinct(provider_parent_org_code)) |>
    filter(n_parents > 1) |>
    nrow(),

  # q15: top 5 NHS trusts by Type 1 attendances (incl. booked), Sep 2026
  q15 = ae_month("2026-09") |>
    filter(is_nhs_trust(org_code)) |>
    top_n_strict("attendances_type1_all", 5, "org_code"),

  # q16: top 3 treatment functions (excluding C_999) by pathways, Aug 2026
  q16 = rtt |>
    filter(period == month("2026-08"), !is_all_specialties_total) |>
    group_by(treatment_function_code) |>
    summarise(pathways = sum(total_incomplete)) |>
    top_n_strict("pathways", 3, "treatment_function_code"),

  # q17: emergency admissions via A&E as % of attendances, Sep 2026
  q17 = with(ae_month("2026-09"), pct_of(emergency_admissions_via_ae, attendances_total)),

  # q18: RA7 Jul 2026 minus (RA7 + RVJ) Jun 2026, like for like across the merger
  q18 = sum(c999_month("2026-07") |> filter(provider_org_code == "RA7") |> pull(total_incomplete)) -
    sum(c999_month("2026-06") |> filter(provider_org_code %in% c("RA7", "RVJ")) |> pull(total_incomplete)),

  # q19: like-for-like national change Oct -> Nov 2025 (providers in both months)
  q19 = local({
    oct <- c999_month("2025-10")
    nov <- c999_month("2025-11")
    both <- intersect(oct$provider_org_code, nov$provider_org_code)
    sum(nov$total_incomplete[nov$provider_org_code %in% both]) -
      sum(oct$total_incomplete[oct$provider_org_code %in% both])
  }),

  # q20: 5 NHS trusts (>= 10,000 pathways) with the lowest % within 18 weeks, Aug 2026
  q20 = c999_month("2026-08") |>
    filter(is_nhs_trust(provider_org_code), total_incomplete >= 10000) |>
    mutate(pct_18 = within_18_weeks / known_clock_start) |>
    top_n_strict("pct_18", 5, "provider_org_code", decreasing = FALSE),

  # --- v1.1 ---

  # q21: top 3 ICBs by incomplete pathways, built from provider C_999 rows, Aug 2026
  q21 = c999_month("2026-08") |>
    group_by(provider_parent_org_code) |>
    summarise(pathways = sum(total_incomplete), .groups = "drop") |>
    top_n_strict("pathways", 3, "provider_parent_org_code"),

  # q22: all 7 regions by all-types 4-hour performance, Sep 2026, lowest first
  q22 = local({
    regions <- ae_month("2026-09") |>
      group_by(parent_org) |>
      summarise(pct = 100 - pct_of(over_4hrs_total, attendances_total), .groups = "drop")
    stopifnot("q22 expects 7 regions" = nrow(regions) == 7, "q22 has tied regions" = !anyDuplicated(regions$pct))
    regions$parent_org[order(regions$pct)]
  }),

  # q23: refusal. The A&E table has no December 2026.
  q23 = refusal_key(
    proof = !any(ae$period == month("2026-12")),
    keywords = c("September 2026", "Sep 2026", "2026-09", "not in the data", "not available", "no data",
                 "only covers", "only goes", "latest", "ends", "beyond", "outside")
  ),

  # q24: refusal. RTT counts pathways; no column counts unique patients.
  q24 = refusal_key(
    proof = !any(grepl("patient", names(rtt), ignore.case = TRUE)),
    keywords = c("pathway")
  ),

  # q25: refusal. The only 12-hour columns are measured from the decision to admit.
  q25 = refusal_key(
    proof = all(startsWith(grep("12", names(ae), value = TRUE), "dta")),
    keywords = c("decision to admit", "decision-to-admit", "DTA", "ECDS", "trolley")
  ),

  # q26: NHS trusts in both tables, Aug 2026, with > 70,000 pathways and Type 1 4-hour < 60%
  q26 = local({
    rtt_trusts <- c999_month("2026-08") |>
      filter(is_nhs_trust(provider_org_code)) |>
      select(org_code = provider_org_code, pathways = total_incomplete)
    ae_type1 <- ae_month("2026-08") |>
      filter(attendances_type1_all > 0) |>
      mutate(pct_type1 = 100 * (1 - over_4hrs_type1_all / attendances_type1_all)) |>
      select(org_code, pct_type1)
    both <- inner_join(rtt_trusts, ae_type1, by = "org_code")
    stopifnot("q26 has a trust exactly on a threshold" = !any(both$pathways == 70000 | both$pct_type1 == 60))
    sum(both$pathways > 70000 & both$pct_type1 < 60)
  }),

  # q27: RAL Aug 2026 minus (RAL + RAP) Oct 2024, like for like across the merger
  q27 = pathways_of("RAL", "2026-08") - pathways_of(c("RAL", "RAP"), "2024-10"),

  # q28: change Sep 2024 -> Aug 2026, providers with a C_999 row in every month
  q28 = pathways_of(providers_every_month, "2026-08") - pathways_of(providers_every_month, "2024-09"),

  # q29: like-for-like month-to-month falls (providers present in both months)
  q29 = local({
    months <- sort(unique(c999$period))
    falls <- vapply(2:length(months), function(i) {
      prev <- filter(c999, period == months[i - 1])
      curr <- filter(c999, period == months[i])
      both <- intersect(prev$provider_org_code, curr$provider_org_code)
      sum(curr$total_incomplete[curr$provider_org_code %in% both]) <
        sum(prev$total_incomplete[prev$provider_org_code %in% both])
    }, logical(1))
    sum(falls)
  }),

  # q30: 3 NHS trusts (every month, no mergers) with the largest % fall, Sep 2024 -> Aug 2026
  q30 = local({
    merger_trusts <- c("RA7", "RVJ", "RAL", "RAP")
    keep <- function(df) filter(df, provider_org_code %in% providers_every_month,
                                is_nhs_trust(provider_org_code), !provider_org_code %in% merger_trusts)
    sep24 <- keep(c999_month("2024-09")) |> select(code = provider_org_code, sep24 = total_incomplete)
    aug26 <- keep(c999_month("2026-08")) |> select(code = provider_org_code, aug26 = total_incomplete)
    inner_join(sep24, aug26, by = "code") |>
      mutate(pct_change = (aug26 - sep24) / sep24) |>
      top_n_strict("pct_change", 3, "code", decreasing = FALSE)
  })
)

# Attach each question's answer type and units from questions.yaml, and check
# every answer has the expected shape.
questions <- yaml::read_yaml(QUESTIONS_PATH)$questions
ids <- vapply(questions, `[[`, "", "id")
unknown <- setdiff(names(answers), ids)
if (length(unknown)) stop("answers for questions not in questions.yaml: ", toString(unknown))

# A question with no entry above has no ground truth yet: it is left out of
# answers.json, and the eval runner skips it.
pending <- setdiff(ids, names(answers))
if (length(pending)) cat("No ground truth yet (skipped):", toString(pending), "\n")
questions <- Filter(function(q) q$id %in% names(answers), questions)

# A refusal is written list(refusal = TRUE, keywords = c(...)): the keywords
# are what a reason must mention to explain why the data can't answer.
expected_length <- function(q) {
  if (q$answer_type == "ranking list") length(answers[[q$id]]) else 1L
}
out <- lapply(questions, function(q) {
  value <- answers[[q$id]]
  if (q$answer_type == "refusal") {
    if (!isTRUE(value$refusal) || length(value$keywords) == 0) stop(q$id, " needs list(refusal = TRUE, keywords = c(...))")
    return(list(id = q$id, answer_type = q$answer_type, units = q$units, answer = value))
  }
  if (length(value) != expected_length(q) || anyNA(value)) {
    stop(q$id, " has an unexpected answer: length ", length(value), ", NA: ", anyNA(value))
  }
  if (q$answer_type == "yes/no") value <- if (isTRUE(value)) "yes" else "no"
  list(id = q$id, answer_type = q$answer_type, units = q$units, answer = value)
})

result <- list(
  data_as_of = DATA_AS_OF,
  source_rows = list(rtt = nrow(rtt), ae = nrow(ae)),
  answers = out
)
jsonlite::write_json(result, OUT_PATH, auto_unbox = TRUE, pretty = TRUE, digits = NA)
cat("Wrote", length(out), "answers to", OUT_PATH, "\n")

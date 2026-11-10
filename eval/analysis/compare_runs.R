# Compare the agent's eval runs across development stages.
#
# Stages (set with `run_eval.py --label <stage>`):
#   baseline  - the baseline agent, unchanged
#   fixes     - + harness fixes (no answer-type check; packages pre-loaded)
#   refusal   - + the option to refuse questions the data can't answer
#
# For each stage it reports accuracy, right-first-time, retries, cost per
# question and false refusals, overall and split into q01-q20 and q21-q30.
# Accuracy and right-first-time get 95% bootstrap intervals that resample
# questions (not runs), because the question set is the main source of
# uncertainty: a different set of 30 questions could give a different score.
#
# Outputs (in docs/results/):
#   stage_comparison.csv   one row per stage and question set
#   stage_comparison.png   accuracy and right-first-time with 95% intervals
#   question_results.csv   one row per stage, run and question (the raw data)
#
# Run from the repo root:  Rscript eval/analysis/compare_runs.R

# ---- Packages ---------------------------------------------------------------
# suppressPackageStartupMessages() just hides the "attaching package" notes.
suppressPackageStartupMessages({
  library(dplyr)    # filter(), mutate(), summarise() ... for tables
  library(tidyr)    # pivot_longer(): reshape a table from wide to long
  library(purrr)    # map(): run a function on every item of a list
  library(ggplot2)  # the chart
  library(boot)     # bootstrap confidence intervals
})

# ---- Settings ---------------------------------------------------------------
RUNS_DIR <- "eval/runs"          # where run_eval.py saves every run
OUT_DIR <- "docs/results"        # where this script saves its results
MODEL <- "claude-haiku-5-5"      # only compare runs on this model
N_BOOT <- 2000                   # how many bootstrap resamples to draw

# The stage labels used in run.json, in order, with a readable name for each.
STAGES <- c(baseline = "Baseline", fixes = "+ harness fixes", refusal = "+ refusal option")

# The bootstrap draws random samples. Fixing the "seed" makes the random
# numbers, and so the intervals, the same every time the script runs.
set.seed(2026)

# ---- Step 1: find the runs for each stage -------------------------------------
# Every run folder has a run.json describing it. Read them all, then keep the
# live (not --mock) runs on the chosen model that ran all 30 questions and
# carry one of the stage labels.
run_dirs <- list.dirs(RUNS_DIR, recursive = FALSE)

runs <- map(run_dirs, function(dir) {
  meta <- jsonlite::read_json(file.path(dir, "run.json"))
  tibble(
    run_dir = dir,
    run_id = basename(dir),
    stage = meta$label %||% NA_character_,   # %||% means "use the right side if the left is NULL"
    model = meta$model,
    mock = isTRUE(meta$mock),
    n_questions = length(meta$questions)
  )
}) |>
  list_rbind()   # stack the one-row tables into one table

runs <- runs |>
  filter(stage %in% names(STAGES), !mock, model == MODEL, n_questions == 30)

# Stop with a clear message if a stage has no runs yet.
missing <- setdiff(names(STAGES), runs$stage)
if (length(missing) > 0) stop("No runs found for stage(s): ", toString(missing))

cat("Runs per stage:\n")
print(count(runs, stage))

# ---- Step 2: read every question's result -----------------------------------
# Each run has one JSON file per question in its questions/ folder. Read each
# into a one-row table, then stack them all.
read_question <- function(path, run_id, stage) {
  q <- jsonlite::read_json(path)
  # A refusal answer looks like {"refused": true, "reason": "..."}.
  refused <- is.list(q$answer) && isTRUE(q$answer$refused)
  tibble(
    stage = stage,
    run_id = run_id,
    id = q$id,
    pass = isTRUE(q$grade$pass),        # graded correct?
    retries = q$retries,                # 0 or 1
    cost_usd = q$cost_usd,
    refused = refused,
    reason = if (refused) q$answer$reason else NA_character_
  )
}

results <- pmap(runs, function(run_dir, run_id, stage, ...) {
  files <- list.files(file.path(run_dir, "questions"), pattern = "\\.json$", full.names = TRUE)
  map(files, read_question, run_id = run_id, stage = stage) |> list_rbind()
}) |>
  list_rbind()

# ---- Step 3: add what each question is ---------------------------------------
# questions.yaml says which questions expect a refusal (the data can't answer).
questions <- yaml::read_yaml("eval/questions.yaml")$questions
refusal_ids <- map_chr(Filter(function(q) q$answer_type == "refusal", questions), "id")

results <- results |>
  mutate(
    stage = factor(stage, levels = names(STAGES), labels = STAGES),  # keeps stages in order
    question_set = if_else(id <= "q20", "q01-q20", "q21-q30"),
    refusal_question = id %in% refusal_ids,
    # Right first time = correct without needing the retry.
    right_first_time = pass & retries == 0,
    # A false refusal is refusing a question the data CAN answer.
    false_refusal = refused & !refusal_question
  )

# ---- Step 4: a bootstrap interval, resampling questions -----------------------
# For one stage: average each question's score over the runs (e.g. 2 of 3 runs
# correct = 0.67), then take the mean over questions. That mean is the point
# estimate. The bootstrap repeatedly draws a new set of questions *with
# replacement* (some appear twice, some not at all), recomputes the mean, and
# uses the middle 95% of those means as the interval.
bootstrap_ci <- function(per_question_scores) {
  estimate <- mean(per_question_scores)
  # If every question scored the same (e.g. all 1), every resample gives the
  # same mean, so the interval is just that value.
  if (length(unique(per_question_scores)) == 1) return(c(estimate, estimate, estimate))
  b <- boot(per_question_scores, statistic = function(x, i) mean(x[i]), R = N_BOOT)
  ci <- boot.ci(b, type = "perc")$percent[4:5]   # columns 4 and 5 hold the lower and upper limits
  c(estimate, ci)
}

# ---- Step 5: summarise each stage --------------------------------------------
# Returns one row of measures for a set of results.
summarise_results <- function(df) {
  per_question <- df |>
    group_by(id) |>
    summarise(accuracy = mean(pass), right_first_time = mean(right_first_time), .groups = "drop")
  acc <- bootstrap_ci(per_question$accuracy)
  rft <- bootstrap_ci(per_question$right_first_time)
  n_runs <- n_distinct(df$run_id)
  tibble(
    runs = n_runs,
    questions = n_distinct(df$id),
    accuracy = acc[1], accuracy_lo = acc[2], accuracy_hi = acc[3],
    right_first_time = rft[1], right_first_time_lo = rft[2], right_first_time_hi = rft[3],
    retries_per_run = sum(df$retries) / n_runs,
    cost_per_question_usd = mean(df$cost_usd),
    # Share of the refusal questions (q23-q25) answered with a correct refusal.
    # NA when this group has no refusal questions (q01-q20).
    refusal_accuracy = if (any(df$refusal_question)) mean(df$pass[df$refusal_question]) else NA_real_,
    false_refusals = sum(df$false_refusal)
  )
}

# Summarise every stage for all 30 questions, then for each half separately.
all_questions <- results |> mutate(question_set = "all 30")
comparison <- bind_rows(all_questions, results) |>
  group_by(stage, question_set) |>
  group_modify(~ summarise_results(.x)) |>   # run summarise_results() on each group
  ungroup() |>
  arrange(question_set, stage)

# ---- Step 6: print and save the table ----------------------------------------
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)
print(comparison, width = Inf)
readr::write_csv(comparison, file.path(OUT_DIR, "stage_comparison.csv"))
readr::write_csv(results |> arrange(stage, run_id, id), file.path(OUT_DIR, "question_results.csv"))

# Any false refusals, with the reason the agent gave.
false_refusals <- results |> filter(false_refusal) |> select(stage, run_id, id, reason)
cat("\nFalse refusals:", nrow(false_refusals), "\n")
if (nrow(false_refusals) > 0) print(false_refusals, width = Inf)

# ---- Step 7: the chart -------------------------------------------------------
# Reshape to "long" format: one row per stage, question set and measure, which
# is what ggplot wants for colouring by measure.
chart_data <- comparison |>
  # Give the point estimates an "_est" ending so every column is <measure>_<part>.
  select(stage, question_set,
         accuracy_est = accuracy, accuracy_lo, accuracy_hi,
         right_first_time_est = right_first_time, right_first_time_lo, right_first_time_hi) |>
  # Split each column name into the measure and the part (est, lo or hi);
  # ".value" turns the parts into three columns.
  pivot_longer(
    cols = -c(stage, question_set),
    names_to = c("measure", ".value"),
    names_pattern = "(accuracy|right_first_time)_(est|lo|hi)"
  ) |>
  mutate(measure = recode(measure, accuracy = "Accuracy", right_first_time = "Right first time"))

chart <- ggplot(chart_data, aes(x = stage, y = est, colour = measure)) +
  geom_pointrange(aes(ymin = lo, ymax = hi), position = position_dodge(width = 0.4)) +
  facet_wrap(~question_set) +
  scale_y_continuous(labels = scales::percent, limits = c(0, 1)) +
  labs(
    title = "Agent accuracy by development stage",
    subtitle = sprintf("Claude Haiku 5.5, 3 runs per stage; 95%% bootstrap intervals over questions (%d resamples)", N_BOOT),
    x = NULL, y = NULL, colour = NULL
  ) +
  theme_minimal(base_size = 11) +
  theme(legend.position = "bottom", axis.text.x = element_text(angle = 20, hjust = 1))

ggsave(file.path(OUT_DIR, "stage_comparison.png"), chart, width = 9, height = 4.5, dpi = 150, bg = "white")
cat("\nSaved", file.path(OUT_DIR, c("stage_comparison.csv", "stage_comparison.png", "question_results.csv")), sep = "\n  ")

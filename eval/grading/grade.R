# grade_answer(id, answer): grade one answer against eval/ground_truth/answers.json.
#
# Uses the grading rules in eval/questions.yaml:
#   number        PASS if within 1% relative error
#   count         PASS if exactly equal
#   ranking list  PASS if the same items in the same order
#   yes/no        PASS if exactly equal ("yes"/"no" or TRUE/FALSE)
#   refusal       PASS if the answer is a refusal whose reason says why the data
#                 can't answer: it must be at least MIN_REASON_CHARS long and
#                 mention at least one of the question's keywords
#
# A refusal is written refusal("reason"). Refusing a question that has an
# answer always FAILs, and so does answering a question that needs a refusal.
#
# Returns a list(id, pass, detail) invisibly and prints a one-line verdict.
# Run from the repo root:  source("eval/grading/grade.R")

ANSWERS_PATH <- "eval/ground_truth/answers.json"
NUMBER_TOLERANCE <- 0.01
MIN_REASON_CHARS <- 20

# The answer for a question the data can't answer.
refusal <- function(reason) list(refused = TRUE, reason = as.character(reason))

is_refusal <- function(x) is.list(x) && !is.data.frame(x) && isTRUE(x$refused)

load_answers <- function(path = ANSWERS_PATH) {
  key <- jsonlite::read_json(path, simplifyVector = TRUE)
  setNames(split(key$answers, seq_len(nrow(key$answers))), key$answers$id)
}

as_yes_no <- function(x) {
  if (is.logical(x)) return(if (isTRUE(x)) "yes" else "no")
  tolower(trimws(as.character(x)))
}

grade_refusal <- function(answer, want) {
  if (!is_refusal(answer)) {
    return(list(pass = FALSE, detail = "the data can't answer this question; expected refusal(\"why ...\")"))
  }
  reason <- paste(answer$reason, collapse = " ")
  keywords <- unlist(want$keywords)
  # Case-insensitive literal match (grepl ignores ignore.case when fixed = TRUE).
  explains <- any(vapply(tolower(keywords), grepl, logical(1), x = tolower(reason), fixed = TRUE))
  if (nchar(reason) < MIN_REASON_CHARS || !explains) {
    return(list(pass = FALSE, detail = "refused, but the reason doesn't say why the data can't answer it"))
  }
  list(pass = TRUE, detail = "")
}

grade_answer <- function(id, answer, answers = load_answers()) {
  if (!id %in% names(answers)) stop("Unknown question id: ", id)
  expected <- answers[[id]]
  type <- expected$answer_type
  want <- expected$answer[[1]]
  if (is.data.frame(answer) && ncol(answer) == 1) answer <- answer[[1]]

  result <- if (type != "refusal" && is_refusal(answer)) {
    list(pass = FALSE, detail = "refused, but the data can answer this question")
  } else switch(type,
    "number" = {
      rel <- (as.numeric(answer) - want) / abs(want)
      list(pass = length(answer) == 1 && !is.na(rel) && abs(rel) <= NUMBER_TOLERANCE,
           detail = sprintf("%+.2f%% from expected", 100 * rel))
    },
    "count" = list(pass = length(answer) == 1 && isTRUE(answer == want), detail = ""),
    "ranking list" = list(
      pass = identical(unname(as.character(answer)), as.character(want)),
      detail = sprintf("%d of %d positions match", sum(as.character(answer)[seq_along(want)] == want, na.rm = TRUE), length(want))
    ),
    "yes/no" = list(pass = length(answer) == 1 && as_yes_no(answer) == want, detail = ""),
    "refusal" = grade_refusal(answer, want),
    stop("Unknown answer type: ", type)
  )

  cat(sprintf("%s %s %s\n", if (result$pass) "PASS" else "FAIL", id, result$detail))
  invisible(list(id = id, pass = result$pass, detail = result$detail))
}

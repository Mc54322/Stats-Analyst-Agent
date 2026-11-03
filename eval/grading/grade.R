# grade_answer(id, answer): grade one answer against eval/ground_truth/answers.json.
#
# Uses the grading rules in eval/questions.yaml:
#   number        PASS if within 1% relative error
#   count         PASS if exactly equal
#   ranking list  PASS if the same items in the same order
#   yes/no        PASS if exactly equal ("yes"/"no" or TRUE/FALSE)
#
# Returns a list(id, pass, detail) invisibly and prints a one-line verdict.
# Run from the repo root:  source("eval/grading/grade.R")

ANSWERS_PATH <- "eval/ground_truth/answers.json"
NUMBER_TOLERANCE <- 0.01

load_answers <- function(path = ANSWERS_PATH) {
  key <- jsonlite::read_json(path, simplifyVector = TRUE)
  setNames(split(key$answers, seq_len(nrow(key$answers))), key$answers$id)
}

as_yes_no <- function(x) {
  if (is.logical(x)) return(if (isTRUE(x)) "yes" else "no")
  tolower(trimws(as.character(x)))
}

grade_answer <- function(id, answer, answers = load_answers()) {
  if (!id %in% names(answers)) stop("Unknown question id: ", id)
  expected <- answers[[id]]
  type <- expected$answer_type
  want <- expected$answer[[1]]
  if (is.data.frame(answer) && ncol(answer) == 1) answer <- answer[[1]]

  result <- switch(type,
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
    stop("Unknown answer type: ", type)
  )

  cat(sprintf("%s %s %s\n", if (result$pass) "PASS" else "FAIL", id, result$detail))
  invisible(list(id = id, pass = result$pass, detail = result$detail))
}

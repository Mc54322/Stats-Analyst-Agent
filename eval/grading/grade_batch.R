# Grade many answers in one go with grade_answer() from grade.R.
#
# Input:  a JSON array of {"id": "q01", "answer": <value or null>}
# Output: a JSON array of {"id", "pass", "detail"}
#
# Run from the repo root:
#   Rscript eval/grading/grade_batch.R answers_in.json grades_out.json

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2) stop("Usage: Rscript eval/grading/grade_batch.R <answers_in.json> <grades_out.json>")

source("eval/grading/grade.R")
key <- load_answers()
items <- jsonlite::read_json(args[1], simplifyVector = FALSE)

grades <- lapply(items, function(item) {
  if (is.null(item$answer)) {
    return(list(id = item$id, pass = FALSE, detail = "no answer"))
  }
  answer <- if (is.list(item$answer)) unlist(item$answer) else item$answer
  graded <- NULL
  invisible(capture.output(graded <- grade_answer(item$id, answer, key)))
  list(id = item$id, pass = isTRUE(graded$pass), detail = graded$detail)
})

jsonlite::write_json(grades, args[2], auto_unbox = TRUE, pretty = TRUE)

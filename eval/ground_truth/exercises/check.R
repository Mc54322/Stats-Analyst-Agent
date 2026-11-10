# check_answer(id, answer): grade your q21-q30 ground truth against the hidden key.
#
# Uses the same rules as eval/grading/grade.R and prints only PASS or FAIL
# (plus how far off you are for numbers). It never prints the expected answer.
# Source it from the project root:
#   source("eval/ground_truth/exercises/check.R")
#
# For questions the data can't answer, write `answer <- refusal("why ...")`.

source("eval/grading/grade.R")

.exercise_key_path <- "eval/ground_truth/exercises/key.rds"

# Blanks in the practice files are written .___ (or .___() for a whole step).
# Running a line that still has one gives this message instead of a confusing error.
if (exists(".___", envir = globalenv(), inherits = FALSE)) rm(".___", envir = globalenv())
makeActiveBinding(".___", function() {
  stop("This line still has a blank (.___) to fill in. Replace .___ with your code.", call. = FALSE)
}, globalenv())

check_answer <- function(id, answer) {
  if (!file.exists(.exercise_key_path)) {
    stop("Can't find ", .exercise_key_path, ". Run R from the project root.", call. = FALSE)
  }
  key <- unserialize(rev(readRDS(.exercise_key_path)))  # stored scrambled
  if (!id %in% names(key)) {
    stop("check_answer() covers q21 to q30. For q01 to q20 use grade_answer().", call. = FALSE)
  }
  expected <- key[[id]]
  answers <- setNames(list(list(id = id, answer_type = expected$type, answer = list(expected$value))), id)
  invisible(grade_answer(id, answer, answers))
}

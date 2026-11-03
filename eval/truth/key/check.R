# check_answer(id, answer): grade your answer against the hidden key.
#
# Prints only PASS or FAIL (plus how far off you are for numbers). It never
# prints the expected answer. Source it from the project root:
#   source("eval/truth/key/check.R")
#
# Grading rules (from eval/questions/questions.yaml):
#   number  - PASS if within 1% of the expected value (relative error)
#   count   - PASS only if exactly equal
#   ranking - PASS only if the same codes in the same order
#   yesno   - PASS only if exactly equal ("yes"/"no" or TRUE/FALSE)

.key_path <- "eval/truth/key/key.rds"

# Blanks in the practice files are written .___ (or .___() for a whole step).
# If you run a line that still has one, you get this message instead of a
# confusing "object not found" error.
if (exists(".___", envir = globalenv(), inherits = FALSE)) rm(".___", envir = globalenv())
makeActiveBinding(".___", function() {
  stop("This line still has a blank (.___) to fill in. Replace .___ with your code.",
       call. = FALSE)
}, globalenv())

.load_key <- function() {
  if (!file.exists(.key_path)) {
    stop("Can't find ", .key_path, ". Make sure R is running from the project root ",
         "(getwd() should end in 'Stats Analyst Agent').", call. = FALSE)
  }
  # The key is stored with its bytes reversed so it can't be read at a glance.
  unserialize(rev(readRDS(.key_path)))
}

# Turn common beginner outputs into a plain value:
# a 1x1 table becomes its single value; a one-column table becomes that column.
.as_plain <- function(answer) {
  if (is.data.frame(answer)) {
    if (ncol(answer) == 1) return(answer[[1]])
    if (nrow(answer) == 1 && ncol(answer) > 1) {
      stop("Your answer is a table with ", ncol(answer), " columns. ",
           "Keep only the column with the answer, e.g. with pull().", call. = FALSE)
    }
    stop("Your answer is a table with ", nrow(answer), " rows and ", ncol(answer),
         " columns. Reduce it to the single value or list the question asks for.", call. = FALSE)
  }
  answer
}

.as_yesno <- function(x) {
  if (is.logical(x)) return(x)
  x <- tolower(trimws(as.character(x)))
  if (x %in% c("yes", "y", "true")) return(TRUE)
  if (x %in% c("no", "n", "false")) return(FALSE)
  NA
}

check_answer <- function(id, answer) {
  key <- .load_key()
  if (!id %in% names(key)) stop("Unknown question id '", id, "'. Use q01 to q20.", call. = FALSE)
  k <- key[[id]]
  a <- .as_plain(answer)

  if (k$type %in% c("number", "count", "yesno") && length(a) != 1) {
    cat("FAIL (", id, "): expected a single value but your answer has ", length(a),
        " values.\n", sep = "")
    return(invisible(FALSE))
  }
  if (length(a) == 1 && is.na(a)) {
    cat("FAIL (", id, "): your answer is NA. Check for missing values (na.rm?) or an empty filter.\n", sep = "")
    return(invisible(FALSE))
  }

  ok <- switch(k$type,
    number = {
      if (!is.numeric(a)) { cat("FAIL (", id, "): expected a number.\n", sep = ""); return(invisible(FALSE)) }
      rel <- (a - k$value) / abs(k$value)
      pass <- abs(rel) <= 0.01
      cat(if (pass) "PASS" else "FAIL", " (", id, "): ",
          sprintf("%+.2f%% from the expected value", 100 * rel),
          if (pass) "" else " (needs to be within 1%)", "\n", sep = "")
      pass
    },
    count = {
      if (!is.numeric(a)) { cat("FAIL (", id, "): expected a whole number.\n", sep = ""); return(invisible(FALSE)) }
      pass <- a == k$value
      cat(if (pass) "PASS" else "FAIL", " (", id, ")", if (!pass) ": counts must match exactly", "\n", sep = "")
      pass
    },
    ranking = {
      a <- as.character(a)
      pass <- identical(unname(a), k$value)
      if (pass) {
        cat("PASS (", id, ")\n", sep = "")
      } else if (length(a) != length(k$value)) {
        cat("FAIL (", id, "): expected ", length(k$value), " items in order, you gave ", length(a), ".\n", sep = "")
      } else {
        cat("FAIL (", id, "): ", sum(a == k$value), " of ", length(k$value),
            " positions are right.\n", sep = "")
      }
      pass
    },
    yesno = {
      yn <- .as_yesno(a)
      if (is.na(yn)) { cat("FAIL (", id, "): answer \"yes\" or \"no\" (or TRUE/FALSE).\n", sep = ""); return(invisible(FALSE)) }
      pass <- yn == k$value
      cat(if (pass) "PASS" else "FAIL", " (", id, ")\n", sep = "")
      pass
    }
  )
  invisible(ok)
}

"""Grader tests for the refusal answer type (runs eval/grading/grade.R with a
test key; no model, no sandbox)."""

import json
import subprocess

import pytest

from tests.conftest import PROJECT_ROOT

GRADE = """
source("eval/grading/grade.R")
key <- list(
  r1 = list(id = "r1", answer_type = "refusal",
            answer = list(list(refusal = TRUE, keywords = c("pathway", "decision to admit")))),
  n1 = list(id = "n1", answer_type = "number", answer = list(100))
)
cases <- list(
  good   = list("r1", refusal("The data counts RTT pathways, not unique patients.")),
  other_case = list("r1", refusal("Twelve-hour waits here start at the Decision To Admit.")),
  vague  = list("r1", refusal("Sorry, I can't answer that one.")),
  short  = list("r1", refusal("pathways")),
  number = list("r1", 12345),
  wrong_refusal = list("n1", refusal("The data counts pathways, not patients at all.")),
  number_ok = list("n1", 100.5)
)
out <- lapply(cases, function(c) { r <- NULL; invisible(capture.output(r <- grade_answer(c[[1]], c[[2]], key))); r$pass })
cat(jsonlite::toJSON(out, auto_unbox = TRUE))
"""


@pytest.fixture(scope="module")
def results():
    proc = subprocess.run(["Rscript", "-e", GRADE], cwd=PROJECT_ROOT, capture_output=True, text=True)
    assert proc.returncode == 0, proc.stderr
    return json.loads(proc.stdout.strip().splitlines()[-1])


def test_refusal_with_a_reason_passes(results):
    assert results["good"] is True


def test_refusal_keywords_ignore_case(results):
    assert results["other_case"] is True


def test_refusal_without_saying_why_fails(results):
    assert results["vague"] is False      # no keyword
    assert results["short"] is False      # keyword, but too short to be a reason


def test_answering_a_refusal_question_fails(results):
    assert results["number"] is False


def test_refusing_an_answerable_question_fails(results):
    assert results["wrong_refusal"] is False
    assert results["number_ok"] is True   # normal grading is unchanged

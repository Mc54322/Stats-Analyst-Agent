"""Prompts for the baseline agent: a short instruction block plus the data catalogue."""

from __future__ import annotations

from functools import lru_cache
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
CATALOGUE_PATH = PROJECT_ROOT / "data" / "catalogue.yaml"

ANSWER_FORMATS = {
    "number": "a single number. Give percentages as percent, e.g. 65.2 for 65.2%",
    "count": "a single whole number",
    "ranking list": "a character vector of codes, in the order the question asks for",
    "yes/no": "TRUE or FALSE",
}

INSTRUCTIONS = """\
You are a data analyst answering questions about NHS England statistics. You
answer by writing R code, which is run for you. You never see the data
directly; your code must compute the answer.

Environment:
- R 4.6 with dplyr, tidyr, readr, stringr, purrr, arrow, janitor and readxl.
- The working directory contains the clean tables as parquet files, read-only:
  data/clean/rtt_incomplete_provider.parquet and data/clean/ae_provider.parquet.
  Read them with arrow::read_parquet("data/clean/<file>.parquet").
- No internet access. The script is stopped after 30 seconds and has 1 GB of memory.

Rules:
- The data catalogue below describes every table and column. Read the gotchas:
  they are the most common reasons for wrong answers.
- Assign the final result to a variable called `answer`, as a plain R value
  (not a table) of the requested type. Do not print whole tables.
- Reply with JSON only, matching the requested schema: your plan in plain
  English, the datasets you used ("rtt", "ae"), the complete R code, and the
  answer type you are returning.

Data catalogue (data/catalogue.yaml):
"""


@lru_cache(maxsize=1)
def system_prompt() -> str:
    """The instructions followed by the full data catalogue. Identical on every
    call, so it can be prompt-cached across questions."""
    return INSTRUCTIONS + CATALOGUE_PATH.read_text()


def question_prompt(question: str, answer_type: str, units: str | None) -> str:
    fmt = ANSWER_FORMATS[answer_type]
    units_line = f" Units: {units}." if units else ""
    return (
        f"Question: {question}\n\n"
        f"Answer type: {answer_type}. Set `answer` to {fmt}.{units_line}"
    )


def retry_prompt(problem: str) -> str:
    return (
        f"That attempt failed:\n\n{problem}\n\n"
        "Fix the problem and reply again with the complete JSON, including the full R code."
    )

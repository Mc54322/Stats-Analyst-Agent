"""The structured reply the model must return, and the answer formats the eval expects."""

from __future__ import annotations

import math
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field

AnswerType = Literal["number", "count", "ranking list", "yes/no"]
Dataset = Literal["rtt", "ae"]


class AgentReply(BaseModel):
    """What the model returns for each attempt."""

    model_config = ConfigDict(extra="forbid")

    plan: str = Field(description="The steps, in plain English, that the code follows.")
    datasets: list[Dataset] = Field(description="Which tables the code reads.")
    r_code: str = Field(description="Complete R code that assigns the final result to `answer`.")
    answer_type: AnswerType = Field(description="The type of value assigned to `answer`.")


def reply_json_schema() -> dict:
    """JSON schema for structured output (output_config.format)."""
    schema = AgentReply.model_json_schema()
    schema["additionalProperties"] = False
    return schema


REPLY_OUTPUT_CONFIG = {"format": {"type": "json_schema", "schema": reply_json_schema()}}


class AnswerFormatError(ValueError):
    """The R code ran but `answer` isn't in the format the question needs."""


def coerce_answer(value, answer_type: str):
    """Convert the value R produced into the eval's format, or explain why not."""
    if answer_type == "ranking list":
        items = value if isinstance(value, list) else [value]
        if not items or not all(isinstance(x, str) and x for x in items):
            raise AnswerFormatError(
                f"`answer` must be a non-empty character vector of codes, got {value!r}."
            )
        return items

    if isinstance(value, list):
        if len(value) != 1:
            raise AnswerFormatError(f"`answer` must be a single value, got {len(value)} values: {value!r}.")
        value = value[0]

    if answer_type == "yes/no":
        if isinstance(value, bool):
            return "yes" if value else "no"
        if isinstance(value, str) and value.strip().lower() in {"yes", "no"}:
            return value.strip().lower()
        raise AnswerFormatError(f"`answer` must be TRUE or FALSE, got {value!r}.")

    if isinstance(value, bool) or not isinstance(value, (int, float)) or value is None:
        raise AnswerFormatError(f"`answer` must be a number, got {value!r}.")
    if not math.isfinite(value):
        raise AnswerFormatError(f"`answer` must be a finite number, got {value!r}.")

    if answer_type == "count":
        if float(value) != int(value):
            raise AnswerFormatError(f"`answer` must be a whole number, got {value!r}.")
        return int(value)
    return float(value)

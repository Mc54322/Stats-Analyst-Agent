"""Baseline agent: answer a question by having the model write R, then running it.

One question flows like this:
  1. Send the system prompt (instructions + data catalogue) and the question.
  2. The model replies with JSON: plan, datasets, R code, answer type. The reply
     is validated with pydantic.
  3. The R code runs in the sandbox and must assign `answer`; the value is read
     back and checked against the expected answer type.
  4. If the JSON is invalid, the R code fails, or `answer` has the wrong format,
     the problem is sent back to the model once. At most one retry.

Every model call goes through the client's budget guard. BudgetExceededError is
not caught here: it stops whatever is running.
"""

from __future__ import annotations

import json
from dataclasses import asdict, dataclass, field
from typing import Protocol

from pydantic import ValidationError

from agent import prompts
from agent.schema import REPLY_OUTPUT_CONFIG, AgentReply, AnswerFormatError, coerce_answer
from sandbox import run_r_script

MAX_RETRIES = 1
AGENT_MAX_TOKENS = 8000  # room for adaptive thinking plus the JSON reply
STDERR_FEEDBACK_CHARS = 2000

# Put before the model's code so the core packages are always attached.
PACKAGE_PRELUDE = """# ---- added by the agent runner: core packages ----
suppressPackageStartupMessages({ library(dplyr); library(tidyr); library(arrow) })

"""

# Appended to the model's code so the answer comes back as JSON, whatever it is.
ANSWER_EXPORT = """

# ---- added by the agent runner: export `answer` ----
if (!exists("answer")) stop("The code must assign the final result to a variable called `answer`.")
if (is.data.frame(answer)) {
  if (ncol(answer) != 1) stop("`answer` is a table with ", ncol(answer), " columns; reduce it to a single value or one column.")
  answer <- answer[[1]]
}
jsonlite::write_json(list(answer = answer), "output/answer.json", auto_unbox = TRUE, digits = NA)
"""


# --- model interface ---------------------------------------------------------

@dataclass
class LLMTurn:
    text: str                  # the reply text (JSON expected)
    content: list              # the reply content blocks, appended to the history as-is
    input_tokens: int = 0
    output_tokens: int = 0
    cost_usd: float = 0.0


class LLM(Protocol):
    model: str

    def generate(self, system: str, messages: list[dict]) -> LLMTurn: ...


class ClaudeLLM:
    """The real model, via agent.llm (budget-checked, prompt-cached system prompt)."""

    def __init__(self, model: str | None = None, max_tokens: int = AGENT_MAX_TOKENS):
        from agent.llm import default_model

        self.model = model or default_model()
        self.max_tokens = max_tokens

    def generate(self, system: str, messages: list[dict]) -> LLMTurn:
        from agent.llm import response_text, send

        response, usage = send(
            messages,
            model=self.model,
            system=system,
            cache_system=True,
            max_tokens=self.max_tokens,
            output_config=REPLY_OUTPUT_CONFIG,
        )
        return LLMTurn(
            text=response_text(response),
            content=response.content,
            input_tokens=usage.input_tokens,
            output_tokens=usage.output_tokens,
            cost_usd=usage.cost_usd,
        )


# --- result ------------------------------------------------------------------

@dataclass
class Attempt:
    reply_text: str
    reply: dict | None = None
    problem: str | None = None        # what went wrong, as sent back to the model
    stdout: str = ""
    stderr: str = ""
    exit_code: int | None = None
    timed_out: bool = False
    raw_answer: object = None


@dataclass
class AgentResult:
    question: str
    answer_type: str
    model: str
    answer: object = None
    ok: bool = False
    error: str | None = None
    plan: str | None = None
    datasets: list[str] = field(default_factory=list)
    code: str | None = None
    stdout: str = ""
    stderr: str = ""
    retries: int = 0
    attempts: list[Attempt] = field(default_factory=list)
    messages: list[dict] = field(default_factory=list)
    input_tokens: int = 0
    output_tokens: int = 0
    cost_usd: float = 0.0

    def to_dict(self) -> dict:
        d = asdict(self)
        d["messages"] = [_jsonable_message(m) for m in self.messages]
        return d


def _jsonable_message(message: dict) -> dict:
    content = message["content"]
    if isinstance(content, list):
        content = [b.model_dump() if hasattr(b, "model_dump") else b for b in content]
    return {"role": message["role"], "content": content}


# --- the agent loop ----------------------------------------------------------

def answer_question(
    question: str,
    answer_type: str,
    units: str | None = None,
    *,
    llm: LLM | None = None,
    max_retries: int = MAX_RETRIES,
    timeout_s: int = 30,
) -> AgentResult:
    """Answer one question. Returns the answer, the code, the R output, the
    number of retries used, tokens and cost."""
    llm = llm or ClaudeLLM()
    system = prompts.system_prompt()
    messages: list[dict] = [{"role": "user", "content": prompts.question_prompt(question, answer_type, units)}]
    result = AgentResult(question=question, answer_type=answer_type, model=llm.model, messages=messages)

    for attempt_no in range(max_retries + 1):
        turn = llm.generate(system, messages)
        result.input_tokens += turn.input_tokens
        result.output_tokens += turn.output_tokens
        result.cost_usd += turn.cost_usd
        messages.append({"role": "assistant", "content": turn.content})

        attempt = Attempt(reply_text=turn.text)
        result.attempts.append(attempt)
        attempt.problem = _run_attempt(attempt, turn.text, answer_type, timeout_s, result)

        if attempt.problem is None:
            result.ok = True
            result.error = None
            break
        result.error = attempt.problem
        if attempt_no < max_retries:
            result.retries += 1
            messages.append({"role": "user", "content": prompts.retry_prompt(attempt.problem)})

    result.cost_usd = round(result.cost_usd, 6)
    return result


def _run_attempt(attempt: Attempt, text: str, answer_type: str, timeout_s: int, result: AgentResult) -> str | None:
    """Validate the reply, run its code and read back `answer`. Returns the
    problem to report to the model, or None on success."""
    try:
        reply = AgentReply.model_validate_json(text)
    except ValidationError as exc:
        return f"Your reply was not valid JSON matching the schema:\n{_short_validation(exc)}"
    attempt.reply = reply.model_dump()
    result.plan, result.datasets, result.code = reply.plan, list(reply.datasets), reply.r_code

    # The declared answer_type is informational only: coerce_answer() below
    # checks the value R actually produced against the type the question needs.
    run = run_r_script(PACKAGE_PRELUDE + reply.r_code + ANSWER_EXPORT, timeout_s=timeout_s)
    attempt.stdout, attempt.stderr = run.stdout, run.stderr
    attempt.exit_code, attempt.timed_out = run.exit_code, run.timed_out
    result.stdout, result.stderr = run.stdout, run.stderr

    if run.timed_out:
        return f"The R code was stopped after {timeout_s} seconds. Make it faster."
    if run.oom_killed:
        return "The R code ran out of memory (1 GB limit). Read only the columns and rows you need."
    if run.exit_code != 0:
        return f"The R code failed (exit code {run.exit_code}). Error output:\n{run.stderr[-STDERR_FEEDBACK_CHARS:]}"

    answer_file = run.output_dir / "answer.json"
    if not answer_file.exists():
        return "The R code finished but `answer` was not exported."
    attempt.raw_answer = json.loads(answer_file.read_text()).get("answer")
    try:
        result.answer = coerce_answer(attempt.raw_answer, answer_type)
    except AnswerFormatError as exc:
        return str(exc)
    return None


def _short_validation(exc: ValidationError) -> str:
    return "\n".join(
        f"- {'.'.join(str(p) for p in e['loc']) or '(reply)'}: {e['msg']}" for e in exc.errors()[:5]
    )

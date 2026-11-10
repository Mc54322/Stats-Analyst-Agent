"""Agent loop tests with a scripted fake model (no API calls). They run the
real R sandbox, so they need Docker and the image."""

from agent.core import answer_question
from tests.conftest import ScriptedLLM, reply, requires_sandbox

pytestmark = requires_sandbox

Q07 = ("What was the England total of incomplete RTT pathways in Aug 2026, as recorded "
       "in the RTT table (all providers, all specialties)?")

CORRECT_Q07_CODE = """
library(dplyr)
rtt <- arrow::read_parquet("data/clean/rtt_incomplete_provider.parquet")
answer <- rtt |>
  filter(period == as.Date("2026-08-01"), is_all_specialties_total) |>
  summarise(total = sum(total_incomplete)) |>
  pull(total)
"""

BROKEN_CODE = "answer <- undefined_thing + 1"


def test_correct_answer_is_graded_pass(run_eval):
    llm = ScriptedLLM([reply(CORRECT_Q07_CODE)])

    result = answer_question(Q07, "number", "pathways", llm=llm)
    grades = run_eval.grade({"q07": result})

    assert result.ok and result.retries == 0
    assert result.code == CORRECT_Q07_CODE
    assert grades["q07"]["pass"] is True


def test_broken_r_code_retries_exactly_once_then_stops():
    llm = ScriptedLLM([reply(BROKEN_CODE)] * 3)

    result = answer_question(Q07, "number", "pathways", llm=llm)

    assert len(llm.calls) == 2                       # first try + one retry, never a third
    assert result.retries == 1
    assert not result.ok and result.answer is None
    assert "object 'undefined_thing' not found" in result.error
    # The R error was sent back to the model on the retry.
    retry_message = llm.calls[1][-1]
    assert retry_message["role"] == "user" and "undefined_thing" in retry_message["content"]
    assert [m["role"] for m in result.messages] == ["user", "assistant", "user", "assistant"]


def test_invalid_json_triggers_a_retry():
    llm = ScriptedLLM(["this is not JSON", reply(CORRECT_Q07_CODE)])

    result = answer_question(Q07, "number", "pathways", llm=llm)

    assert len(llm.calls) == 2
    assert result.retries == 1
    assert result.ok
    assert "not valid JSON" in result.attempts[0].problem
    assert "not valid JSON" in llm.calls[1][-1]["content"]


def test_declared_answer_type_mismatch_is_not_a_retry():
    # The value is a valid number; only the declared label differs. No retry.
    llm = ScriptedLLM([reply(CORRECT_Q07_CODE, answer_type="count")])

    result = answer_question(Q07, "number", "pathways", llm=llm)

    assert result.ok and result.retries == 0 and len(llm.calls) == 1


def test_core_packages_are_preloaded():
    # %>% and filter() work without library(dplyr) in the model's code.
    code = ('rtt <- read_parquet("data/clean/rtt_incomplete_provider.parquet")\n'
            "answer <- rtt %>% filter(is_all_specialties_total) %>% nrow()")
    llm = ScriptedLLM([reply(code, answer_type="count")])

    result = answer_question("How many C_999 rows are there?", "count", "rows", llm=llm)

    assert result.ok and result.retries == 0, result.error


def test_refusal_needs_no_r_code(monkeypatch):
    import agent.core

    def no_sandbox(*args, **kwargs):
        raise AssertionError("a refusal must not run any R code")

    monkeypatch.setattr(agent.core, "run_r_script", no_sandbox)
    reason = "The RTT data counts pathways, not unique patients."
    llm = ScriptedLLM([reply("", refusal_reason=reason)])

    result = answer_question("How many unique patients were waiting?", "number", "patients", llm=llm)

    assert result.ok and result.retries == 0
    assert result.answer == {"refused": True, "reason": reason}


def test_reply_without_code_or_refusal_is_sent_back():
    llm = ScriptedLLM([reply(""), reply(CORRECT_Q07_CODE)])

    result = answer_question(Q07, "number", "pathways", llm=llm)

    assert result.retries == 1 and result.ok
    assert "r_code is required" in result.attempts[0].problem


def test_wrong_answer_format_is_sent_back():
    # A two-value answer for a single-number question is a format problem, not a crash.
    llm = ScriptedLLM([reply("answer <- c(1, 2)"), reply("answer <- 3")])

    result = answer_question(Q07, "number", "pathways", llm=llm)

    assert result.retries == 1 and result.ok and result.answer == 3.0
    assert "single value" in result.attempts[0].problem

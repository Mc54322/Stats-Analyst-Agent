"""Pre-run check for isTRUE()/isFALSE() inside filter() (no model, no sandbox)."""

import pytest

import agent.core
from agent.core import answer_question, scalar_tests_in_filter
from tests.conftest import ScriptedLLM, reply


@pytest.mark.parametrize("code", [
    "ae |> filter(isFALSE(has_ae_activity))",
    "ae %>% filter(period == as.Date('2026-09-01'), isTRUE(has_ae_activity))",
    "dplyr::filter(ae, isFALSE(has_ae_activity)) |> nrow()",
    "filter(ae,\n  period == max(period),\n  isFALSE(has_ae_activity)\n)",
    "filter(ae, !isTRUE(has_ae_activity))",
])
def test_scalar_test_inside_filter_is_caught(code):
    assert scalar_tests_in_filter(code)


@pytest.mark.parametrize("code", [
    "ae |> filter(!has_ae_activity)",
    "ae |> filter(has_ae_activity == FALSE)",
    "ae |> filter(has_ae_activity)",
    "if (isTRUE(nrow(ae) > 0)) answer <- 1",                     # isTRUE() outside filter()
    "ok <- isFALSE(any(is.na(ae$org_code)))\nae |> filter(!has_ae_activity)",
    'ae |> filter(org_name != "isFALSE(x)")',                     # inside a string
    "ae |> filter(!has_ae_activity)  # not isFALSE(has_ae_activity)",  # inside a comment
    "is_filtered <- TRUE; my_filter(isTRUE(x))",                 # a different function
])
def test_allowed_code_is_not_flagged(code):
    assert scalar_tests_in_filter(code) == []


def test_flagged_code_is_sent_back_without_running(monkeypatch):
    def no_sandbox(*args, **kwargs):
        raise AssertionError("flagged code must not be run")

    monkeypatch.setattr(agent.core, "run_r_script", no_sandbox)
    bad = "answer <- ae |> filter(isFALSE(has_ae_activity)) |> nrow()"
    llm = ScriptedLLM([reply(bad, answer_type="count"), reply("", refusal_reason="stop: second attempt reached")])

    result = answer_question("How many providers had no A&E attendances?", "count", "providers", llm=llm)

    assert result.retries == 1 and len(llm.calls) == 2
    problem = result.attempts[0].problem
    assert "isFALSE(has_ae_activity)" in problem
    assert "single TRUE or FALSE for the whole column" in problem
    assert "!column" in problem and "column == FALSE" in problem
    assert llm.calls[1][-1]["content"].count("isTRUE() or isFALSE()") == 1

"""scripts/ask.py with a scripted fake model (no API calls). Uses the real sandbox."""

import importlib.util
import json

import pytest

from agent.llm import BudgetExceededError
from tests.conftest import PROJECT_ROOT, ScriptedLLM, reply, requires_sandbox

pytestmark = requires_sandbox

NUMBER_WITH_CHART = """
ae <- read_parquet("data/clean/ae_provider.parquet")
monthly <- ae |> group_by(period) |> summarise(attendances = sum(attendances_total))
ggplot2::ggsave("output/attendances.png", ggplot2::ggplot(monthly, ggplot2::aes(period, attendances)) + ggplot2::geom_line(),
                width = 6, height = 4)
answer <- monthly |> filter(period == max(period)) |> pull(attendances)
"""

TABLE = """
ae <- read_parquet("data/clean/ae_provider.parquet")
answer <- ae |> filter(period == as.Date("2026-09-01")) |> group_by(parent_org) |>
  summarise(attendances = sum(attendances_total)) |> arrange(parent_org)
"""


@pytest.fixture(scope="module")
def ask():
    spec = importlib.util.spec_from_file_location("ask", PROJECT_ROOT / "scripts" / "ask.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def saved(asked_dir):
    return sorted(asked_dir.iterdir())


def test_answer_plan_code_cost_and_chart_are_printed_and_saved(ask, tmp_path, capsys):
    llm = ScriptedLLM([reply(NUMBER_WITH_CHART, datasets=("ae",))])

    code = ask.main(["How many A&E attendances were there in the latest month?"], llm=llm, asked_dir=tmp_path)

    out = capsys.readouterr().out
    assert code == 0
    assert "Answer: 2,444,743" in out           # Sep 2026 national total (eval q11 inputs)
    assert "Plan:\n  test plan" in out
    assert "R code:" in out and "ggsave" in out
    assert "Retries: 0" in out and "Cost: $0.0000" in out

    (folder,) = saved(tmp_path)
    chart = folder / "attendances.png"
    assert chart.exists() and chart.stat().st_size > 0
    assert f"Chart: {chart}" in out
    record = json.loads((folder / "result.json").read_text())
    assert record["question"].startswith("How many A&E")
    assert record["answer"] == 2444743 and record["plots"] == [str(chart)]
    assert record["code"] == NUMBER_WITH_CHART


def test_table_answer_is_printed_as_rows(ask, tmp_path, capsys):
    llm = ScriptedLLM([reply(TABLE, datasets=("ae",))])

    ask.main(["A&E attendances by region in Sep 2026?"], llm=llm, asked_dir=tmp_path)

    out = capsys.readouterr().out
    assert "parent_org" in out and "attendances" in out
    assert "NHS ENGLAND LONDON" in out
    record = json.loads((saved(tmp_path)[0] / "result.json").read_text())
    assert len(record["answer"]) == 7                   # seven regions


def test_named_values_print_as_label_value_pairs(ask, tmp_path, capsys):
    code = ('rtt <- read_parquet("data/clean/rtt_incomplete_provider.parquet") |>\n'
            '  filter(period == as.Date("2026-08-01"), is_all_specialties_total)\n'
            "answer <- c(incomplete_pathways = sum(rtt$total_incomplete),\n"
            "            pct_within_18_weeks = sum(rtt$within_18_weeks) / sum(rtt$known_clock_start))")
    llm = ScriptedLLM([reply(code)])

    ask.main(["Pathways and 18-week share, Aug 2026?"], llm=llm, asked_dir=tmp_path)

    out = capsys.readouterr().out
    assert "Answer:\n  incomplete_pathways: 7,189,213\n  pct_within_18_weeks: 0.6516" in out
    record = json.loads((saved(tmp_path)[0] / "result.json").read_text())
    assert record["answer"]["incomplete_pathways"] == 7189213


def test_refusal_and_reason_are_printed(ask, tmp_path, capsys):
    reason = "The RTT data counts pathways, not unique patients."
    llm = ScriptedLLM([reply("", refusal_reason=reason)])

    ask.main(["How many unique patients are waiting?"], llm=llm, asked_dir=tmp_path)

    out = capsys.readouterr().out
    assert "Refused: the data can't answer this question." in out
    assert reason in out and "R code:" not in out
    record = json.loads((saved(tmp_path)[0] / "result.json").read_text())
    assert record["answer"] == {"refused": True, "reason": reason}


def test_interactive_mode_asks_until_quit(ask, tmp_path, capsys):
    llm = ScriptedLLM([reply(TABLE, datasets=("ae",)), reply("", refusal_reason="Not in the data: ends Sep 2026.")])
    inputs = iter(["A&E attendances by region?", "", "What about December 2026?", "quit", "never asked"])

    code = ask.main(["--interactive"], llm=llm, asked_dir=tmp_path, input_fn=lambda prompt: next(inputs))

    assert code == 0
    assert len(llm.calls) == 2 and len(saved(tmp_path)) == 2      # blank line skipped, stops at quit
    assert "Type quit to stop" in capsys.readouterr().out


def test_spend_cap_stops_the_session_cleanly(ask, tmp_path, capsys):
    class CappedLLM:
        model = "capped"

        def generate(self, system, messages):
            raise BudgetExceededError("Spend cap reached: this run has spent $2.00 of its $2.00 budget.")

    code = ask.main(["--interactive"], llm=CappedLLM(), asked_dir=tmp_path,
                    input_fn=lambda prompt: "Any question")

    assert code == 2
    assert "Spend cap reached" in capsys.readouterr().err

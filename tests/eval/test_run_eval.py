"""Eval runner tests (no API calls). They run the real R sandbox and grader."""

import json
import re
from types import SimpleNamespace

import anthropic
import pytest

from agent.llm import budget, client
from tests.conftest import requires_sandbox

pytestmark = requires_sandbox

ANSWER_FOR_TYPE = {"number": "1", "count": "1", "yes/no": "TRUE", "ranking list": 'c("AAA")'}


class FakeAnthropic:
    """Stands in for anthropic.Anthropic behind the real ClaudeLLM + budget guard."""

    def __init__(self, input_tokens=10_000, output_tokens=500):
        self.creates = 0
        self._in, self._out = input_tokens, output_tokens
        api = SimpleNamespace(create=self._create, count_tokens=self._count)
        self.messages = api
        self.beta = SimpleNamespace(messages=api)

    def _count(self, **kwargs):
        return SimpleNamespace(input_tokens=self._in)

    def _create(self, **kwargs):
        self.creates += 1
        prompt = kwargs["messages"][0]["content"]
        answer_type = re.search(r"Answer type: (.+?)\. Set", prompt).group(1)
        text = json.dumps({"plan": "p", "datasets": ["rtt"], "answer_type": answer_type,
                           "r_code": f"answer <- {ANSWER_FOR_TYPE[answer_type]}"})
        return SimpleNamespace(
            model="claude-haiku-5-5", stop_reason="end_turn", stop_details=None,
            content=[SimpleNamespace(type="text", text=text)],
            usage=SimpleNamespace(input_tokens=self._in, output_tokens=self._out,
                                  cache_creation_input_tokens=0, cache_read_input_tokens=0,
                                  iterations=None),
        )


@pytest.fixture
def fake_api(monkeypatch, tmp_path):
    monkeypatch.setenv("ANTHROPIC_API_KEY", "test-key")
    monkeypatch.setenv("SPEND_LEDGER_PATH", str(tmp_path / "ledger.json"))
    monkeypatch.setattr(client, "_load_env", lambda: None)
    monkeypatch.setattr(anthropic, "Anthropic", lambda *a, **k: (_ for _ in ()).throw(
        AssertionError("tests must not create a real Anthropic client")))
    fake = FakeAnthropic()
    monkeypatch.setattr(client, "_client", lambda: fake)
    budget.reset_tracker()
    yield fake
    budget.reset_tracker()


def test_budget_guard_stops_a_run_cleanly_mid_eval(run_eval, fake_api, monkeypatch, tmp_path):
    # Each call: worst case (10,000 x $0.125 + 8,000 x $0.50) / 1e6 = $0.00525;
    # actual (10,000 x $0.10 + 500 x $0.50) / 1e6 = $0.00125.
    # With a $0.007 cap, two questions fit and the third is refused before sending.
    monkeypatch.setenv("BUDGET_USD", "0.007")
    runs = tmp_path / "runs"

    code = run_eval.main(["--questions", "q01", "q02", "q05", "q07"], runs_dir=runs)

    assert code == 2
    assert fake_api.creates == 2
    (run_dir,) = runs.iterdir()
    meta = json.loads((run_dir / "run.json").read_text())
    assert "spend cap reached before q05" in meta["summary"]["stopped_reason"]
    assert meta["summary"]["questions_attempted"] == 2
    assert sorted(p.name for p in (run_dir / "questions").iterdir()) == ["q01.json", "q02.json"]
    assert meta["summary"]["total_cost_usd"] == pytest.approx(2 * 0.00125)
    assert len(budget.read_ledger(tmp_path / "ledger.json")) == 2


def test_full_mock_run_over_all_questions_writes_the_run_folder(run_eval, tmp_path):
    runs = tmp_path / "runs"

    code = run_eval.main(["--mock"], runs_dir=runs)

    assert code == 0
    (run_dir,) = runs.iterdir()
    meta = json.loads((run_dir / "run.json").read_text())
    files = sorted(p.name for p in (run_dir / "questions").iterdir())
    assert files == [f"q{i:02d}.json" for i in range(1, 21)]
    assert meta["model"] == "mock" and meta["system_prompt"]
    assert meta["summary"]["passed"] == 20 and meta["summary"]["total_cost_usd"] == 0
    record = json.loads((run_dir / "questions" / "q15.json").read_text())
    assert record["grade"]["pass"] is True and record["code"] and record["messages"]

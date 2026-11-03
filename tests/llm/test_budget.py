"""Budget guard tests. No network: the Claude client is replaced by a fake."""

from types import SimpleNamespace

import anthropic
import pytest

from agent.llm import budget, client
from agent.llm.budget import BudgetExceededError

# Rates from agent/llm/pricing.toml, per million tokens.
HAIKU_IN, HAIKU_OUT = 0.10, 0.50
HAIKU_LONG_IN, HAIKU_LONG_OUT = 0.50, 2.50
SONNET_IN, SONNET_OUT = 2.00, 10.00


def usage(input_tokens, output_tokens, iterations=None):
    return SimpleNamespace(
        input_tokens=input_tokens,
        output_tokens=output_tokens,
        cache_creation_input_tokens=0,
        cache_read_input_tokens=0,
        iterations=iterations,
    )


class FakeClient:
    """Stands in for anthropic.Anthropic: fixed token counts, no network."""

    def __init__(self, input_tokens=1_000, output_tokens=200, model="claude-haiku-5-5", iterations=None):
        self.created = []
        self._counted = input_tokens
        self._response = SimpleNamespace(
            model=model,
            stop_reason="end_turn",
            stop_details=None,
            content=[SimpleNamespace(type="text", text="hello")],
            usage=usage(input_tokens, output_tokens, iterations),
        )
        create = SimpleNamespace(create=self._create, count_tokens=self._count)
        self.messages = create
        self.beta = SimpleNamespace(messages=create)

    def _count(self, **kwargs):
        return SimpleNamespace(input_tokens=self._counted)

    def _create(self, **kwargs):
        self.created.append(kwargs)
        return self._response


@pytest.fixture(autouse=True)
def isolated(monkeypatch, tmp_path):
    """Fresh run, temp ledger, fake key, and no way to build a real client."""
    monkeypatch.setenv("ANTHROPIC_API_KEY", "test-key")
    monkeypatch.setenv("SPEND_LEDGER_PATH", str(tmp_path / "ledger.json"))
    monkeypatch.delenv("BUDGET_USD", raising=False)
    monkeypatch.delenv("LLM_MODEL", raising=False)
    monkeypatch.setattr(client, "_load_env", lambda: None)

    def no_real_client(*args, **kwargs):
        raise AssertionError("tests must not create a real Anthropic client")

    monkeypatch.setattr(anthropic, "Anthropic", no_real_client)
    budget.reset_tracker()
    yield tmp_path / "ledger.json"
    budget.reset_tracker()


def use(monkeypatch, fake):
    monkeypatch.setattr(client, "_client", lambda: fake)
    return fake


def test_call_under_cap_succeeds_and_costs_the_right_amount(monkeypatch, isolated):
    fake = use(monkeypatch, FakeClient(input_tokens=1_000, output_tokens=200))

    text, u = client.complete_with_usage("say hello", max_tokens=256)

    assert text == "hello"
    assert len(fake.created) == 1
    expected = (1_000 * HAIKU_IN + 200 * HAIKU_OUT) / 1e6
    assert u.cost_usd == pytest.approx(expected)
    assert u.run_spent_usd == pytest.approx(expected)
    assert u.run_budget_usd == 5.0


def test_call_that_could_exceed_cap_is_refused_before_sending(monkeypatch, isolated):
    monkeypatch.setenv("BUDGET_USD", "0.001")
    fake = use(monkeypatch, FakeClient(input_tokens=1_000))

    # Worst case: 1,000 input (at the $0.125 cache-write rate) + 16,000 output = $0.0081, over the $0.001 cap.
    with pytest.raises(BudgetExceededError, match=r"spent \$0\.0000 of its \$0\.0010 budget.*up to \$0\.0081"):
        client.complete_with_usage("say hello", max_tokens=16_000)

    assert fake.created == []          # the request was never sent
    assert budget.read_ledger(isolated) == []


def test_cap_stops_a_run_once_spent_and_says_how_much(monkeypatch, isolated):
    # $0.002 cap; each call's worst case is (1,000 * 0.125 + 2,000 * 0.50) / 1e6 = $0.001125,
    # and each call actually costs (1,000 * 0.10 + 2,000 * 0.50) / 1e6 = $0.0011.
    monkeypatch.setenv("BUDGET_USD", "0.002")
    fake = use(monkeypatch, FakeClient(input_tokens=1_000, output_tokens=2_000))

    client.complete_with_usage("first", max_tokens=2_000)       # spends $0.0011
    with pytest.raises(BudgetExceededError) as err:
        client.complete_with_usage("second", max_tokens=2_000)  # $0.0011 + $0.0011 > $0.002

    assert "$0.0011" in str(err.value)
    assert "Stopping" in str(err.value)
    assert len(fake.created) == 1


def test_ledger_records_each_call_and_accumulates_across_runs(monkeypatch, isolated):
    use(monkeypatch, FakeClient(input_tokens=1_000, output_tokens=200))

    client.complete_with_usage("one", max_tokens=256)
    client.complete_with_usage("two", max_tokens=256)
    first_run = budget.get_tracker().run_id

    budget.reset_tracker()                        # a new process = a new run
    client.complete_with_usage("three", max_tokens=256)

    entries = budget.read_ledger(isolated)
    per_call = (1_000 * HAIKU_IN + 200 * HAIKU_OUT) / 1e6
    assert len(entries) == 3
    assert [e["run_id"] == first_run for e in entries] == [True, True, False]
    for e in entries:
        assert e["model"] == "claude-haiku-5-5"
        assert (e["input_tokens"], e["output_tokens"]) == (1_000, 200)
        assert e["cost_usd"] == pytest.approx(per_call)
        assert e["timestamp"]
    assert budget.total_spent_usd(isolated) == pytest.approx(3 * per_call)
    assert budget.get_tracker().spent_usd == pytest.approx(per_call)   # new run starts at 0


def test_haiku_long_prompt_uses_higher_rates(monkeypatch, isolated):
    use(monkeypatch, FakeClient(input_tokens=150_000, output_tokens=100))

    _, u = client.complete_with_usage("long", max_tokens=256)

    assert u.cost_usd == pytest.approx((150_000 * HAIKU_LONG_IN + 100 * HAIKU_LONG_OUT) / 1e6)


def test_sonnet_fallback_is_priced_per_model_attempt(monkeypatch, isolated):
    # A declined Sonnet 5.5 attempt followed by the Sonnet 5 fallback that served it.
    iterations = [
        SimpleNamespace(model="claude-sonnet-5-5", input_tokens=500, output_tokens=50,
                        cache_creation_input_tokens=0, cache_read_input_tokens=0),
        SimpleNamespace(model="claude-sonnet-5", input_tokens=500, output_tokens=300,
                        cache_creation_input_tokens=0, cache_read_input_tokens=0),
    ]
    fake = use(monkeypatch, FakeClient(input_tokens=1_000, output_tokens=350,
                                       model="claude-sonnet-5", iterations=iterations))

    _, u = client.complete_with_usage("hi", model="claude-sonnet-5-5", max_tokens=1_000)

    assert fake.created[0]["fallbacks"] == "default"
    assert u.cost_usd == pytest.approx((1_000 * SONNET_IN + 350 * SONNET_OUT) / 1e6)


def test_sonnet_worst_case_allows_for_a_paid_fallback(monkeypatch, isolated):
    # Input priced at the 5-minute cache-write rate ($2.50), output at $10, doubled for the fallback.
    estimate = budget.worst_case_cost_usd("claude-sonnet-5-5", input_tokens=1_000, max_tokens=1_000)
    assert estimate == pytest.approx(2 * (1_000 * 2.50 + 1_000 * SONNET_OUT) / 1e6)


def test_invalid_budget_is_rejected(monkeypatch, isolated):
    monkeypatch.setenv("BUDGET_USD", "five dollars")
    use(monkeypatch, FakeClient())
    with pytest.raises(ValueError, match="BUDGET_USD must be a number"):
        client.complete_with_usage("hi")


def test_unpriced_model_is_refused_before_sending(monkeypatch, isolated):
    fake = use(monkeypatch, FakeClient(model="claude-unknown"))
    with pytest.raises(budget.PricingError):
        client.complete_with_usage("hi", model="claude-unknown")
    assert fake.created == []

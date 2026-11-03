"""Spend cap and cost ledger for Claude API calls.

A "run" is one Python process: one eval run, one smoke test, one app session.
Each run may spend at most BUDGET_USD (from .env, default 5). Before every call
the worst-case cost is checked against what is left of the run's budget; after
every call the actual cost is computed from the usage the API returns and
appended to a cumulative ledger (.spend/ledger.json, gitignored).
"""

from __future__ import annotations

import json
import os
import tomllib
import uuid
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from functools import lru_cache
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[2]
PRICING_PATH = Path(__file__).with_name("pricing.toml")
DEFAULT_LEDGER_PATH = PROJECT_ROOT / ".spend" / "ledger.json"
DEFAULT_BUDGET_USD = 5.0
PER_MILLION = 1_000_000

# The server-side refusal fallback for Claude Sonnet 5.5 retries declined
# requests on Claude Sonnet 5. A request that is declined part-way through is
# billed and then re-run, so in the worst case one call is paid for twice.
FALLBACK_MODELS = {"claude-sonnet-5-5": ["claude-sonnet-5"]}
FALLBACK_WORST_CASE_MULTIPLIER = 2


def _usd(amount: float) -> str:
    """$5.00 for whole amounts, $0.0011 for fractions of a cent."""
    return f"${amount:.2f}" if amount >= 1 else f"${amount:.4f}"


class BudgetExceededError(RuntimeError):
    """Raised before a call that could push this run past its spend cap."""


class PricingError(RuntimeError):
    """Raised when a model has no price in pricing.toml."""


# --- pricing ---------------------------------------------------------------

@lru_cache(maxsize=1)
def load_pricing() -> dict:
    with PRICING_PATH.open("rb") as f:
        return tomllib.load(f)


def rates(model: str, prompt_tokens: int = 0) -> dict:
    """Per-million-token rates for a model at a given prompt length."""
    models = load_pricing()["models"]
    if model not in models:
        raise PricingError(
            f"No price for model '{model}' in {PRICING_PATH.name}. "
            "Add it from the official pricing page before calling it."
        )
    entry = models[model]
    threshold = entry.get("long_prompt_threshold")
    if threshold is not None and prompt_tokens > threshold:
        return entry["long_prompt"]
    return entry


def cost_usd(
    model: str,
    input_tokens: int,
    output_tokens: int,
    cache_creation_input_tokens: int = 0,
    cache_read_input_tokens: int = 0,
) -> float:
    """Cost of one model attempt. Cache writes are priced at the 5-minute rate."""
    prompt_tokens = input_tokens + cache_creation_input_tokens + cache_read_input_tokens
    r = rates(model, prompt_tokens)
    return (
        input_tokens * r["input"]
        + output_tokens * r["output"]
        + cache_creation_input_tokens * r["cache_write_5m"]
        + cache_read_input_tokens * r["cache_read"]
    ) / PER_MILLION


def worst_case_cost_usd(model: str, input_tokens: int, max_tokens: int) -> float:
    """Upper bound for one call: every input token plus max_tokens of output."""
    candidates = [model, *FALLBACK_MODELS.get(model, [])]
    worst = max(cost_usd(m, input_tokens, max_tokens) for m in candidates)
    if model in FALLBACK_MODELS:
        worst *= FALLBACK_WORST_CASE_MULTIPLIER
    return worst


def response_cost_usd(response) -> float:
    """Actual cost of a response, from the usage the API returned.

    When a fallback ran, usage.iterations lists each model attempt with its own
    token counts, so each attempt is priced at its own model's rates.
    """
    usage = response.usage
    iterations = getattr(usage, "iterations", None)
    if iterations:
        return sum(
            cost_usd(
                getattr(it, "model", None) or response.model,
                it.input_tokens,
                it.output_tokens,
                getattr(it, "cache_creation_input_tokens", 0) or 0,
                getattr(it, "cache_read_input_tokens", 0) or 0,
            )
            for it in iterations
        )
    return cost_usd(
        response.model,
        usage.input_tokens,
        usage.output_tokens,
        getattr(usage, "cache_creation_input_tokens", 0) or 0,
        getattr(usage, "cache_read_input_tokens", 0) or 0,
    )


# --- run budget and ledger ---------------------------------------------------

@dataclass
class LedgerEntry:
    timestamp: str
    run_id: str
    model_requested: str
    model: str
    input_tokens: int
    output_tokens: int
    cache_creation_input_tokens: int
    cache_read_input_tokens: int
    estimated_max_cost_usd: float
    cost_usd: float
    cost_is_estimate: bool = False  # True if the served model had no price


class SpendTracker:
    """Tracks one run's spend against its cap and appends every call to the ledger."""

    def __init__(self, budget_usd: float, ledger_path: Path):
        self.budget_usd = budget_usd
        self.ledger_path = ledger_path
        self.run_id = f"{datetime.now(timezone.utc):%Y%m%dT%H%M%SZ}-{uuid.uuid4().hex[:6]}"
        self.spent_usd = 0.0

    @property
    def remaining_usd(self) -> float:
        return self.budget_usd - self.spent_usd

    def check(self, estimated_max_cost_usd: float) -> None:
        """Refuse a call whose worst-case cost would take the run past its cap."""
        if self.spent_usd + estimated_max_cost_usd > self.budget_usd:
            raise BudgetExceededError(
                f"Spend cap reached: this run has spent {_usd(self.spent_usd)} of its "
                f"{_usd(self.budget_usd)} budget, and the next call could cost up to "
                f"{_usd(estimated_max_cost_usd)}. Stopping. Raise BUDGET_USD in .env "
                f"or lower max_tokens to continue."
            )

    def record(self, *, model_requested: str, response, estimated_max_cost_usd: float) -> LedgerEntry:
        """Add a call's actual cost to the run total and append it to the ledger."""
        usage = response.usage
        # If the API served the request on a model we have no price for, the
        # call has still been made and must be counted: fall back to the
        # worst-case estimate and flag it, rather than recording nothing.
        try:
            actual = response_cost_usd(response)
            is_estimate = False
        except PricingError:
            actual = estimated_max_cost_usd
            is_estimate = True
        entry = LedgerEntry(
            timestamp=datetime.now(timezone.utc).isoformat(timespec="seconds"),
            run_id=self.run_id,
            model_requested=model_requested,
            model=response.model,
            input_tokens=usage.input_tokens,
            output_tokens=usage.output_tokens,
            cache_creation_input_tokens=getattr(usage, "cache_creation_input_tokens", 0) or 0,
            cache_read_input_tokens=getattr(usage, "cache_read_input_tokens", 0) or 0,
            estimated_max_cost_usd=round(estimated_max_cost_usd, 6),
            cost_usd=round(actual, 6),
            cost_is_estimate=is_estimate,
        )
        self.spent_usd += entry.cost_usd
        self._append(entry)
        return entry

    def _append(self, entry: LedgerEntry) -> None:
        self.ledger_path.parent.mkdir(parents=True, exist_ok=True)
        entries = read_ledger(self.ledger_path)
        entries.append(asdict(entry))
        tmp = self.ledger_path.with_suffix(".tmp")
        tmp.write_text(json.dumps(entries, indent=2))
        tmp.replace(self.ledger_path)  # atomic, so a crash can't leave half a file


def read_ledger(path: Path = DEFAULT_LEDGER_PATH) -> list[dict]:
    if not path.exists():
        return []
    return json.loads(path.read_text())


def total_spent_usd(path: Path = DEFAULT_LEDGER_PATH) -> float:
    """Total spend across every run in the ledger."""
    return round(sum(e["cost_usd"] for e in read_ledger(path)), 6)


def _budget_from_env() -> float:
    raw = os.environ.get("BUDGET_USD", "").strip()
    if not raw:
        return DEFAULT_BUDGET_USD
    try:
        value = float(raw)
    except ValueError:
        raise ValueError(f"BUDGET_USD must be a number of dollars, got {raw!r}.") from None
    if value <= 0:
        raise ValueError(f"BUDGET_USD must be greater than 0, got {value}.")
    return value


_tracker: SpendTracker | None = None


def get_tracker() -> SpendTracker:
    """The tracker for this process (created on first use)."""
    global _tracker
    if _tracker is None:
        ledger = Path(os.environ.get("SPEND_LEDGER_PATH", DEFAULT_LEDGER_PATH))
        _tracker = SpendTracker(_budget_from_env(), ledger)
    return _tracker


def reset_tracker() -> None:
    """Start a new run in this process. Used by tests."""
    global _tracker
    _tracker = None

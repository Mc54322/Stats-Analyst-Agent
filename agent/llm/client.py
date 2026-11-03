"""Thin wrapper around the Claude API: send a prompt, get text back.

The API key is read from ANTHROPIC_API_KEY, loaded from the project's .env file
(see .env.example). The model defaults to Claude Haiku 5.5 for development; pass
``model=FINAL_MODEL`` or set LLM_MODEL in .env to use Claude Sonnet 5.5 for
final evaluation runs.

Every call goes through the spend cap in agent/llm/budget.py: it is refused if
its worst-case cost could take this run past BUDGET_USD, and its actual cost is
written to the ledger afterwards.
"""

from __future__ import annotations

import os
from dataclasses import dataclass
from functools import lru_cache

import anthropic
from dotenv import find_dotenv, load_dotenv

from agent.llm import budget

DEV_MODEL = "claude-haiku-5-5"
FINAL_MODEL = "claude-sonnet-5-5"

# Kept modest because v1 runs under a $5 spend limit. The cap check assumes the
# full max_tokens is used, so a higher value makes calls look more expensive.
DEFAULT_MAX_TOKENS = 4096

# Claude Sonnet 5.5 supports a server-side fallback: if a request is declined
# by a safety classifier, the API retries it on Claude Sonnet 5 within the same
# call. Claude Haiku 5.5 has no server-side fallback.
_FALLBACK_MODELS = set(budget.FALLBACK_MODELS)
_FALLBACK_BETA = "server-side-fallback-2026-07-01"


class LLMRefusalError(RuntimeError):
    """Raised when the model declines the request (stop_reason == "refusal")."""


@dataclass(frozen=True)
class Usage:
    model: str
    input_tokens: int
    output_tokens: int
    cost_usd: float
    run_spent_usd: float
    run_budget_usd: float


def _load_env() -> None:
    load_dotenv(find_dotenv(usecwd=True))


def default_model() -> str:
    """The model to use when none is passed: LLM_MODEL from .env, else Haiku 5.5."""
    _load_env()
    return os.environ.get("LLM_MODEL", DEV_MODEL)


def api_key_configured() -> bool:
    _load_env()
    return bool(os.environ.get("ANTHROPIC_API_KEY"))


@lru_cache(maxsize=1)
def _client() -> anthropic.Anthropic:
    if not api_key_configured():
        raise RuntimeError(
            "ANTHROPIC_API_KEY is not set. Copy .env.example to .env and add your key."
        )
    return anthropic.Anthropic()


def send(
    messages: list[dict],
    *,
    model: str | None = None,
    system: str | None = None,
    cache_system: bool = False,
    max_tokens: int = DEFAULT_MAX_TOKENS,
    output_config: dict | None = None,
):
    """Send a conversation and return (response, usage). Every call is budget-checked.

    ``cache_system`` marks the system prompt for prompt caching, which makes
    repeated calls with the same long system prompt (e.g. the data catalogue)
    much cheaper. ``output_config`` is passed through, e.g. a JSON schema for
    structured output.
    """
    _load_env()
    model = model or default_model()
    request: dict = {"model": model, "max_tokens": max_tokens, "messages": messages}
    if system:
        request["system"] = (
            [{"type": "text", "text": system, "cache_control": {"type": "ephemeral"}}]
            if cache_system else system
        )
    if output_config:
        request["output_config"] = output_config

    client = _client()
    tracker = budget.get_tracker()

    # Before the call: count the input exactly (the token-counting endpoint
    # is free) and refuse if the worst case would exceed what's left.
    count_args = {k: request[k] for k in ("model", "messages", "system", "output_config") if k in request}
    counted = client.messages.count_tokens(**count_args)
    estimate = budget.worst_case_cost_usd(model, counted.input_tokens, max_tokens)
    tracker.check(estimate)

    if model in _FALLBACK_MODELS:
        response = client.beta.messages.create(**request, betas=[_FALLBACK_BETA], fallbacks="default")
    else:
        response = client.messages.create(**request)

    # After the call: record what it actually cost, refused or not.
    entry = tracker.record(model_requested=model, response=response, estimated_max_cost_usd=estimate)

    if response.stop_reason == "refusal":
        category = response.stop_details.category if response.stop_details else None
        raise LLMRefusalError(f"The model declined this request (category: {category}).")

    usage = Usage(
        model=response.model,
        input_tokens=entry.input_tokens,
        output_tokens=entry.output_tokens,
        cost_usd=entry.cost_usd,
        run_spent_usd=round(tracker.spent_usd, 6),
        run_budget_usd=tracker.budget_usd,
    )
    return response, usage


def response_text(response) -> str:
    return "".join(block.text for block in response.content if block.type == "text")


def complete_with_usage(
    prompt: str,
    *,
    model: str | None = None,
    system: str | None = None,
    max_tokens: int = DEFAULT_MAX_TOKENS,
) -> tuple[str, Usage]:
    """Send one prompt and return (text, usage including cost)."""
    response, usage = send(
        [{"role": "user", "content": prompt}], model=model, system=system, max_tokens=max_tokens
    )
    return response_text(response), usage


def complete(
    prompt: str,
    *,
    model: str | None = None,
    system: str | None = None,
    max_tokens: int = DEFAULT_MAX_TOKENS,
) -> str:
    """Send one prompt to Claude and return the reply text."""
    text, _ = complete_with_usage(prompt, model=model, system=system, max_tokens=max_tokens)
    return text

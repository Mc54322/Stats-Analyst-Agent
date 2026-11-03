"""Thin wrapper around the Claude API: send a prompt, get text back.

The API key is read from ANTHROPIC_API_KEY, loaded from the project's .env file
(see .env.example). The model defaults to Claude Haiku 5.5 for development; pass
``model=FINAL_MODEL`` or set LLM_MODEL in .env to use Claude Sonnet 5.5 for
final evaluation runs.
"""

from __future__ import annotations

import os
from dataclasses import dataclass
from functools import lru_cache

import anthropic
from dotenv import find_dotenv, load_dotenv

DEV_MODEL = "claude-haiku-5-5"
FINAL_MODEL = "claude-sonnet-5-5"

# Kept modest because v1 runs under a $5 spend limit. Raise it if answers
# start ending with stop_reason "max_tokens".
DEFAULT_MAX_TOKENS = 4096

# Claude Sonnet 5.5 supports a server-side fallback: if a request is declined
# by a safety classifier, the API retries it on a suitable model within the
# same call. Claude Haiku 5.5 has no server-side fallback.
_FALLBACK_MODELS = {FINAL_MODEL}
_FALLBACK_BETA = "server-side-fallback-2026-07-01"


class LLMRefusalError(RuntimeError):
    """Raised when the model declines the request (stop_reason == "refusal")."""


@dataclass(frozen=True)
class Usage:
    model: str
    input_tokens: int
    output_tokens: int


def default_model() -> str:
    """The model to use when none is passed: LLM_MODEL from .env, else Haiku 5.5."""
    load_dotenv(find_dotenv(usecwd=True))
    return os.environ.get("LLM_MODEL", DEV_MODEL)


@lru_cache(maxsize=1)
def _client() -> anthropic.Anthropic:
    load_dotenv(find_dotenv(usecwd=True))
    if not os.environ.get("ANTHROPIC_API_KEY"):
        raise RuntimeError(
            "ANTHROPIC_API_KEY is not set. Copy .env.example to .env and add your key."
        )
    return anthropic.Anthropic()


def complete_with_usage(
    prompt: str,
    *,
    model: str | None = None,
    system: str | None = None,
    max_tokens: int = DEFAULT_MAX_TOKENS,
) -> tuple[str, Usage]:
    """Send one prompt and return (text, token usage)."""
    model = model or default_model()
    request = {
        "model": model,
        "max_tokens": max_tokens,
        "messages": [{"role": "user", "content": prompt}],
    }
    if system:
        request["system"] = system

    if model in _FALLBACK_MODELS:
        response = _client().beta.messages.create(
            **request, betas=[_FALLBACK_BETA], fallbacks="default"
        )
    else:
        response = _client().messages.create(**request)

    if response.stop_reason == "refusal":
        category = response.stop_details.category if response.stop_details else None
        raise LLMRefusalError(f"The model declined this request (category: {category}).")

    text = "".join(block.text for block in response.content if block.type == "text")
    usage = Usage(
        model=response.model,
        input_tokens=response.usage.input_tokens,
        output_tokens=response.usage.output_tokens,
    )
    return text, usage


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

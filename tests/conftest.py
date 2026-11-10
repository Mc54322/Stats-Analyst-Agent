"""Shared test helpers: a scripted fake model and the eval runner module."""

import importlib.util
import json
from pathlib import Path

import pytest

from agent.core import LLMTurn
from sandbox import docker_available, image_available

PROJECT_ROOT = Path(__file__).resolve().parent.parent

requires_sandbox = pytest.mark.skipif(
    not (docker_available() and image_available()),
    reason="needs Docker running and the stats-agent-sandbox image built",
)


class ScriptedLLM:
    """Fake model that returns the given replies in order and records each call."""

    model = "scripted"

    def __init__(self, replies: list[str]):
        self.replies = list(replies)
        self.calls: list[list[dict]] = []

    def generate(self, system: str, messages: list[dict]) -> LLMTurn:
        self.calls.append([dict(m) for m in messages])
        if not self.replies:
            raise AssertionError("ScriptedLLM was called more times than replies were given")
        text = self.replies.pop(0)
        return LLMTurn(text=text, content=[{"type": "text", "text": text}])


def reply(r_code: str, answer_type: str = "number", datasets=("rtt",), refusal_reason=None) -> str:
    """A valid JSON reply with the given R code (or a refusal, if refusal_reason is set)."""
    return json.dumps({"plan": "test plan", "datasets": list(datasets), "r_code": r_code,
                       "answer_type": answer_type, "refusal_reason": refusal_reason})


@pytest.fixture(scope="session")
def run_eval():
    """eval/run_eval.py imported as a module (eval/ isn't a package)."""
    spec = importlib.util.spec_from_file_location("run_eval", PROJECT_ROOT / "eval" / "run_eval.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

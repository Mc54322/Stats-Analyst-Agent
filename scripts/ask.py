"""Ask the agent your own questions about the NHS RTT and A&E data.

    uv run python scripts/ask.py "How many incomplete RTT pathways were there in England in Aug 2026?"
    uv run python scripts/ask.py --interactive          # keep asking until you type quit
    uv run python scripts/ask.py --model claude-sonnet-5-5 "..."

For each question it prints the answer (or the refusal and why), the plan the
model wrote, the R code it ran, retries, tokens and cost, and the path to any
chart it saved. Every question and its full result are saved to asked/
(gitignored), one folder per question, with any charts copied alongside.

Calls go through the same budget guard as the eval runner: one process is one
run, capped at BUDGET_USD. Needs Docker running (the R sandbox) and
ANTHROPIC_API_KEY in .env.

Exit codes: 0 fine, 1 setup problem, 2 stopped by the spend cap.
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Callable

from agent.core import LLM, AgentResult, ClaudeLLM, answer_question
from agent.llm import BudgetExceededError, LLMRefusalError, api_key_configured, default_model
from sandbox import docker_available, image_available

PROJECT_ROOT = Path(__file__).resolve().parent.parent
ASKED_DIR = PROJECT_ROOT / "asked"
QUIT_WORDS = {"quit", "exit", "q"}
MAX_TABLE_ROWS = 20


# --- formatting --------------------------------------------------------------

def is_refusal(answer) -> bool:
    return isinstance(answer, dict) and answer.get("refused") is True


def format_value(answer) -> str:
    """A readable version of whatever R returned: a value, a list or a table."""
    if isinstance(answer, list) and answer and all(isinstance(r, dict) for r in answer):
        return format_table(answer)
    if isinstance(answer, list):
        return ", ".join(str(v) for v in answer)
    if isinstance(answer, float):
        return f"{answer:,.4g}" if abs(answer) < 1000 else f"{answer:,.0f}"
    if isinstance(answer, int) and not isinstance(answer, bool):
        return f"{answer:,}"
    return str(answer)


def format_table(rows: list[dict]) -> str:
    columns = list(dict.fromkeys(k for row in rows for k in row))
    shown = rows[:MAX_TABLE_ROWS]
    cells = [[str(row.get(c, "")) for c in columns] for row in shown]
    widths = [max(len(c), *(len(r[i]) for r in cells)) for i, c in enumerate(columns)]
    lines = ["  ".join(c.ljust(w) for c, w in zip(columns, widths))]
    lines += ["  ".join(v.ljust(w) for v, w in zip(r, widths)) for r in cells]
    if len(rows) > MAX_TABLE_ROWS:
        lines.append(f"... {len(rows) - MAX_TABLE_ROWS} more rows (see result.json)")
    return "\n".join(lines)


def indent(text: str, prefix: str = "  ") -> str:
    return "\n".join(prefix + line for line in text.splitlines())


def report(result: AgentResult, folder: Path, plots: list[Path]) -> str:
    out = []
    if not result.ok:
        out.append(f"No answer: {result.error}")
    elif is_refusal(result.answer):
        out.append("Refused: the data can't answer this question.")
        out.append(indent(result.answer["reason"]))
    else:
        value = format_value(result.answer)
        out.append(f"Answer:\n{indent(value)}" if "\n" in value else f"Answer: {value}")
    if result.plan:
        out.append(f"\nPlan:\n{indent(result.plan)}")
    if result.code and result.code.strip():
        out.append(f"\nR code:\n{indent(result.code)}")
    out.append(
        f"\nRetries: {result.retries}   Tokens: {result.input_tokens:,} in / {result.output_tokens:,} out"
        f"   Cost: ${result.cost_usd:.4f}"
    )
    for plot in plots:
        out.append(f"Chart: {plot}")
    out.append(f"Saved: {folder}")
    return "\n".join(out)


# --- saving ------------------------------------------------------------------

def save(question: str, result: AgentResult, asked_dir: Path) -> tuple[Path, list[Path]]:
    """Save the question and full result to asked/<timestamp>-<slug>/, copying any charts."""
    slug = re.sub(r"[^a-z0-9]+", "-", question.lower()).strip("-")[:50] or "question"
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    folder = asked_dir / f"{stamp}-{slug}"
    folder.mkdir(parents=True, exist_ok=True)
    plots = []
    for src in map(Path, result.plots):
        if src.exists():
            dest = folder / src.name
            shutil.copy2(src, dest)
            plots.append(dest)
    record = {"asked_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
              "question": question, **result.to_dict(), "plots": [str(p) for p in plots]}
    (folder / "result.json").write_text(json.dumps(record, indent=2, default=str))
    return folder, plots


# --- asking ------------------------------------------------------------------

def ask(question: str, llm: LLM, asked_dir: Path) -> AgentResult:
    """Run one question through the agent, save it and print the report."""
    try:
        result = answer_question(question, None, llm=llm)
    except LLMRefusalError as exc:   # a safety decline by the model, not a data refusal
        result = AgentResult(question=question, answer_type="free", model=llm.model, error=str(exc))
    folder, plots = save(question, result, asked_dir)
    print(report(result, folder, plots), flush=True)
    return result


def main(argv: list[str] | None = None, *, llm: LLM | None = None,
         asked_dir: Path = ASKED_DIR, input_fn: Callable[[str], str] = input) -> int:
    parser = argparse.ArgumentParser(description="Ask the agent a question about the NHS RTT and A&E data.")
    parser.add_argument("question", nargs="?", help="the question, in quotes")
    parser.add_argument("--interactive", "-i", action="store_true", help="keep asking until you type quit")
    parser.add_argument("--model", default=None, help="model ID (default: LLM_MODEL or claude-haiku-5-5)")
    args = parser.parse_args(argv)

    if not args.question and not args.interactive:
        parser.error("give a question, or use --interactive")
    if not (docker_available() and image_available()):
        print("The R sandbox isn't available. Start Docker (e.g. `colima start`) and build the image:\n"
              "  docker build -f sandbox/image/Dockerfile -t stats-agent-sandbox .", file=sys.stderr)
        return 1
    if llm is None:
        if not api_key_configured():
            print("ANTHROPIC_API_KEY is not set. Copy .env.example to .env and add your key.", file=sys.stderr)
            return 1
        llm = ClaudeLLM(model=args.model or default_model())

    try:
        if args.question:
            ask(args.question, llm, asked_dir)
        if args.interactive:
            print(f"Ask about NHS RTT waiting lists (Sep 2024 to Aug 2026) or A&E (Oct 2024 to Sep 2026). "
                  f"Type quit to stop. Model: {llm.model}")
            while True:
                try:
                    question = input_fn("\nQuestion> ").strip()
                except EOFError:
                    break
                if question.lower() in QUIT_WORDS:
                    break
                if question:
                    ask(question, llm, asked_dir)
    except BudgetExceededError as exc:
        print(f"\n{exc}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())

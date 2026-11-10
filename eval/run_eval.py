"""Run the evaluation set through the agent and grade every answer.

    uv run python eval/run_eval.py                          # all questions, Claude Haiku 5.5
    uv run python eval/run_eval.py --questions q01 q07      # a subset
    uv run python eval/run_eval.py --model claude-sonnet-5-5
    uv run python eval/run_eval.py --mock                   # fake LLM, no API calls

Each run is saved to eval/runs/<timestamp>/:
    run.json            model, flags, system prompt, summary
    questions/<id>.json  question, every prompt and response, R code, output, grade, tokens, cost

--mock replaces the model with a fake that writes code returning the expected
answer, or refuses where the expected answer is a refusal. It tests the
plumbing (prompting, sandbox, answer export, refusals, grading, run folder),
not the agent's ability, and costs nothing. A full mock run scores 30/30.

Exit codes: 0 finished, 2 stopped by the spend cap, 3 setup problem.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import tempfile
import time
from datetime import datetime, timezone
from pathlib import Path

import yaml

from agent import prompts
from agent.core import AgentResult, ClaudeLLM, LLMTurn, answer_question
from agent.llm import DEV_MODEL, BudgetExceededError, LLMRefusalError
from sandbox import docker_available, image_available

PROJECT_ROOT = Path(__file__).resolve().parent.parent
QUESTIONS_PATH = PROJECT_ROOT / "eval" / "questions.yaml"
ANSWERS_PATH = PROJECT_ROOT / "eval" / "ground_truth" / "answers.json"
GRADE_BATCH = "eval/grading/grade_batch.R"
DEFAULT_RUNS_DIR = PROJECT_ROOT / "eval" / "runs"


# --- mock model --------------------------------------------------------------

class AnswerKeyLLM:
    """Fake model for --mock: replies with valid JSON whose R code assigns the
    expected answer, or, for a refusal question, refuses with a reason that
    mentions one of the question's keywords. Exercises everything except the
    model itself."""

    model = "mock"

    def __init__(self, answers_path: Path = ANSWERS_PATH):
        key = json.loads(answers_path.read_text())["answers"]
        self.by_question = {prompts.question_prompt(q["question"], agent_answer_type(q), agent_units(q)): q
                            for q in _load_questions()}
        self.answers = {a["id"]: a for a in key}

    def generate(self, system: str, messages: list[dict]) -> LLMTurn:
        q = self.by_question[messages[0]["content"]]
        a = self.answers[q["id"]]
        answer_type = agent_answer_type(q)
        reply = {
            "plan": f"Mock reply for {q['id']}: return the expected answer.",
            "datasets": list(q["datasets"]),
            "r_code": "",
            "answer_type": answer_type,
            "refusal_reason": None,
        }
        if a["answer_type"] == "refusal":
            keywords = a["answer"]["keywords"]
            keyword = keywords if isinstance(keywords, str) else keywords[0]
            reply["refusal_reason"] = f"Mock refusal: the data can't answer this ({keyword})."
        else:
            reply["r_code"] = f"answer <- {_r_literal(a['answer'], answer_type)}\ncat('answer set\\n')"
        text = json.dumps(reply)
        return LLMTurn(text=text, content=[{"type": "text", "text": text}])


def _r_literal(value, answer_type: str) -> str:
    if answer_type == "ranking list":
        return "c(" + ", ".join(json.dumps(v) for v in value) + ")"
    if answer_type == "yes/no":
        return "TRUE" if value == "yes" else "FALSE"
    return repr(value)


# --- helpers -----------------------------------------------------------------

def _load_questions() -> list[dict]:
    return yaml.safe_load(QUESTIONS_PATH.read_text())["questions"]


def _ground_truth_ids() -> set[str]:
    return {a["id"] for a in json.loads(ANSWERS_PATH.read_text())["answers"]}


def agent_answer_type(q: dict) -> str:
    """The answer type to ask the agent for. For a question the data can't
    answer, ask for what the question asks for (asks_for), so the agent isn't
    told in advance that the right answer is a refusal."""
    return q.get("asks_for", q["answer_type"]) if q["answer_type"] == "refusal" else q["answer_type"]


def agent_units(q: dict) -> str | None:
    """Units to give the agent. A refusal question's `units` describe the
    refusal, so the agent gets `asks_for_units` instead."""
    return q.get("asks_for_units") if q["answer_type"] == "refusal" else q["units"]


def grade(results: dict[str, AgentResult]) -> dict[str, dict]:
    """Grade answers with eval/grading/grade.R (one Rscript call for all)."""
    items = [{"id": qid, "answer": r.answer if r.ok else None} for qid, r in results.items()]
    with tempfile.TemporaryDirectory() as tmp:
        src, out = Path(tmp) / "answers.json", Path(tmp) / "grades.json"
        src.write_text(json.dumps(items))
        proc = subprocess.run(["Rscript", GRADE_BATCH, str(src), str(out)],
                              cwd=PROJECT_ROOT, capture_output=True, text=True)
        if proc.returncode != 0:
            raise RuntimeError(f"Grading failed:\n{proc.stderr[-2000:]}")
        return {g["id"]: g for g in json.loads(out.read_text())}


def _write_json(path: Path, data) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2, default=str))


def summarise(questions_run: list[str], results: dict[str, AgentResult], grades: dict[str, dict],
              stopped_reason: str | None, total_questions: int) -> dict:
    passed = sum(1 for qid in results if grades.get(qid, {}).get("pass"))
    attempted = len(results)
    return {
        "questions_requested": len(questions_run),
        "questions_attempted": attempted,
        "passed": passed,
        "accuracy": round(passed / attempted, 4) if attempted else 0.0,
        "first_time_success": sum(1 for r in results.values() if r.ok and r.retries == 0),
        "retries_used": sum(r.retries for r in results.values()),
        "failed_to_produce_answer": sum(1 for r in results.values() if not r.ok),
        "input_tokens": sum(r.input_tokens for r in results.values()),
        "output_tokens": sum(r.output_tokens for r in results.values()),
        "total_cost_usd": round(sum(r.cost_usd for r in results.values()), 6),
        "stopped_reason": stopped_reason,
        "eval_set_size": total_questions,
    }


def print_summary(s: dict, run_dir: Path) -> None:
    print("\n" + "=" * 60)
    if s["stopped_reason"]:
        print(f"STOPPED EARLY: {s['stopped_reason']}")
    print(f"Accuracy:            {s['passed']}/{s['questions_attempted']} ({s['accuracy']:.0%})")
    print(f"Right first time:    {s['first_time_success']}/{s['questions_attempted']}")
    print(f"Retries used:        {s['retries_used']}")
    print(f"No answer produced:  {s['failed_to_produce_answer']}")
    print(f"Tokens:              {s['input_tokens']:,} in / {s['output_tokens']:,} out")
    print(f"Total cost:          ${s['total_cost_usd']:.4f}")
    print(f"Run saved to:        {run_dir}")


# --- main --------------------------------------------------------------------

def main(argv: list[str] | None = None, runs_dir: Path = DEFAULT_RUNS_DIR) -> int:
    parser = argparse.ArgumentParser(description="Run the evaluation set through the agent.")
    parser.add_argument("--model", default=DEV_MODEL, help=f"model ID (default: {DEV_MODEL})")
    parser.add_argument("--questions", nargs="+", metavar="ID", help="question ids to run, e.g. q01 q07")
    parser.add_argument("--mock", action="store_true", help="use a fake LLM (no API calls, no cost)")
    parser.add_argument("--label", default=None, help="free-text label stored in run.json, e.g. a stage name")
    args = parser.parse_args(argv)

    if not (docker_available() and image_available()):
        print("The R sandbox isn't available. Start Docker (e.g. `colima start`) and build the image:\n"
              "  docker build -f sandbox/image/Dockerfile -t stats-agent-sandbox .", file=sys.stderr)
        return 3

    questions = _load_questions()
    if args.questions:
        unknown = set(args.questions) - {q["id"] for q in questions}
        if unknown:
            print(f"Unknown question ids: {', '.join(sorted(unknown))}", file=sys.stderr)
            return 3
        questions = [q for q in questions if q["id"] in set(args.questions)]

    # Only questions with ground truth can be graded; the rest are skipped.
    graded_ids = _ground_truth_ids()
    pending = [q["id"] for q in questions if q["id"] not in graded_ids]
    if pending:
        print(f"Skipping {len(pending)} question(s) with no ground truth yet: {', '.join(pending)}")
    questions = [q for q in questions if q["id"] in graded_ids]
    if not questions:
        print("No questions to run.", file=sys.stderr)
        return 3

    llm = AnswerKeyLLM() if args.mock else ClaudeLLM(model=args.model)
    run_dir = runs_dir / datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    meta = {
        "started_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "model": llm.model,
        "mock": args.mock,
        "label": args.label,
        "questions": [q["id"] for q in questions],
        "skipped_no_ground_truth": pending,
        "system_prompt": prompts.system_prompt(),
    }
    _write_json(run_dir / "run.json", meta)

    results: dict[str, AgentResult] = {}
    stopped_reason = None
    for q in questions:
        print(f"{q['id']} ...", end=" ", flush=True)
        start = time.monotonic()
        try:
            result = answer_question(q["question"], agent_answer_type(q), agent_units(q), llm=llm)
        except BudgetExceededError as exc:
            stopped_reason = f"spend cap reached before {q['id']}: {exc}"
            print("stopped (spend cap)")
            break
        except LLMRefusalError as exc:
            result = AgentResult(question=q["question"], answer_type=q["answer_type"],
                                 model=llm.model, error=str(exc))
        results[q["id"]] = result
        status = "answered" if result.ok else "no answer"
        print(f"{status} (retries {result.retries}, ${result.cost_usd:.4f}, {time.monotonic() - start:.1f}s)")
        _write_json(run_dir / "questions" / f"{q['id']}.json", {"id": q["id"], **result.to_dict()})

    grades = grade(results) if results else {}
    for qid, result in results.items():
        _write_json(run_dir / "questions" / f"{qid}.json",
                    {"id": qid, **result.to_dict(), "grade": grades.get(qid)})

    summary = summarise([q["id"] for q in questions], results, grades, stopped_reason, len(_load_questions()))
    meta.update(finished_at=datetime.now(timezone.utc).isoformat(timespec="seconds"), summary=summary)
    _write_json(run_dir / "run.json", meta)
    print_summary(summary, run_dir)
    return 2 if stopped_reason else 0


if __name__ == "__main__":
    sys.exit(main())

"""One-off check that the Claude API key and client work.

Sends "say hello" and prints the reply, the token usage and the cost. Costs a
fraction of a cent on Claude Haiku 5.5, and goes through the BUDGET_USD cap.

    uv run python scripts/smoke_test_llm.py
    uv run python scripts/smoke_test_llm.py --model claude-sonnet-5-5
"""

import argparse
import sys

from agent.llm import BudgetExceededError, api_key_configured, complete_with_usage, default_model


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--model", default=None, help="model ID (default: LLM_MODEL or claude-haiku-5-5)")
    args = parser.parse_args()

    if not api_key_configured():
        print(
            "ANTHROPIC_API_KEY is not set, so no call was made.\n"
            "Copy .env.example to .env, add your key, then run this again.",
            file=sys.stderr,
        )
        return 1

    model = args.model or default_model()
    try:
        text, usage = complete_with_usage("say hello", model=model, max_tokens=256)
    except BudgetExceededError as exc:
        print(exc, file=sys.stderr)
        return 2

    print(f"Model requested: {model}")
    print(f"Model used:      {usage.model}")
    print(f"Reply:           {text.strip()}")
    print(f"Input tokens:    {usage.input_tokens}")
    print(f"Output tokens:   {usage.output_tokens}")
    print(f"Cost:            ${usage.cost_usd:.6f}")
    print(f"Run spend:       ${usage.run_spent_usd:.6f} of ${usage.run_budget_usd:.2f}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

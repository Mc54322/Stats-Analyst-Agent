"""One-off check that the Claude API key and client work.

Sends "say hello" and prints the reply and the token usage. Costs a fraction
of a cent on Claude Haiku 5.5.

    uv run python scripts/smoke_test_llm.py
    uv run python scripts/smoke_test_llm.py --model claude-sonnet-5-5
"""

import argparse

from agent.llm import complete_with_usage, default_model


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--model", default=None, help="model ID (default: LLM_MODEL or claude-haiku-5-5)")
    args = parser.parse_args()

    model = args.model or default_model()
    text, usage = complete_with_usage("say hello", model=model, max_tokens=256)

    print(f"Model requested: {model}")
    print(f"Model used:      {usage.model}")
    print(f"Reply:           {text.strip()}")
    print(f"Input tokens:    {usage.input_tokens}")
    print(f"Output tokens:   {usage.output_tokens}")


if __name__ == "__main__":
    main()

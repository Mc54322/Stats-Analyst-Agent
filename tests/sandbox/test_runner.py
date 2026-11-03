"""Sandbox tests. They need Docker running and the image built:

    docker build -f sandbox/image/Dockerfile -t stats-agent-sandbox .
    uv run pytest tests/sandbox
"""

import re
from pathlib import Path

import pytest

from sandbox import docker_available, image_available, run_r_script

R_SCRIPTS = Path(__file__).parent / "r_scripts"

pytestmark = [
    pytest.mark.skipif(not docker_available(), reason="Docker is not installed or not running"),
    pytest.mark.skipif(
        docker_available() and not image_available(),
        reason="sandbox image not built (see sandbox/image/Dockerfile)",
    ),
]


def test_reads_parquet_from_read_only_data():
    result = run_r_script(R_SCRIPTS / "read_parquet.R")

    assert result.ok, result.stderr
    match = re.search(r"rows:\s*(\d+)", result.stdout)
    assert match and int(match.group(1)) > 0


def test_network_access_fails():
    result = run_r_script(R_SCRIPTS / "network_access.R")

    assert result.exit_code != 0
    assert "NETWORK REACHABLE" not in result.stdout

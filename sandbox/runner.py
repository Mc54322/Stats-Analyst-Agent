"""Run an R script inside the locked-down Docker sandbox.

Each call starts a fresh container from the ``stats-agent-sandbox`` image with:
  - no network (``--network none``)
  - data/clean mounted read-only at /work/data/clean
  - a time limit (default 30 s), enforced inside the container and backed up here
  - a memory limit (default 1 GB, no swap)
  - a read-only root filesystem, no Linux capabilities, a non-root user

The script runs with /work as its working directory, so code written for the
project (``read_parquet("data/clean/...")``) works unchanged. Anything the
script saves to ``output/`` comes back to the host.
"""

from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
import time
import uuid
from dataclasses import dataclass, field
from pathlib import Path

IMAGE = "stats-agent-sandbox"
PROJECT_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_DATA_DIR = PROJECT_ROOT / "data" / "clean"
# Run folders live inside the project (gitignored) rather than the system temp
# folder, because Docker on macOS can only mount folders it has been given access to.
DEFAULT_RUNS_DIR = PROJECT_ROOT / ".sandbox-runs"

TIMEOUT_EXIT_CODE = 124  # what `timeout` returns when the limit is hit
_HOST_GRACE_S = 15  # extra time for container start-up before the host gives up
PLOT_SUFFIXES = {".png", ".jpg", ".jpeg", ".svg", ".pdf"}


@dataclass
class SandboxResult:
    stdout: str
    stderr: str
    exit_code: int
    timed_out: bool
    oom_killed: bool
    duration_s: float
    output_dir: Path
    plots: list[Path] = field(default_factory=list)

    @property
    def ok(self) -> bool:
        return self.exit_code == 0 and not self.timed_out and not self.oom_killed


def docker_available() -> bool:
    """True if the docker CLI exists and the daemon answers."""
    if shutil.which("docker") is None:
        return False
    return subprocess.run(["docker", "info"], capture_output=True).returncode == 0


def image_available(image: str = IMAGE) -> bool:
    return subprocess.run(["docker", "image", "inspect", image], capture_output=True).returncode == 0


def run_r_script(
    script: str | Path,
    *,
    timeout_s: int = 30,
    memory: str = "1g",
    data_dir: Path = DEFAULT_DATA_DIR,
    runs_dir: Path = DEFAULT_RUNS_DIR,
    image: str = IMAGE,
) -> SandboxResult:
    """Run R code (a string, or a path to a .R file) in the sandbox."""
    code = Path(script).read_text() if isinstance(script, Path) else script

    runs_dir.mkdir(parents=True, exist_ok=True)
    run_dir = Path(tempfile.mkdtemp(prefix="run-", dir=runs_dir))
    script_path = run_dir / "script.R"
    script_path.write_text(code)
    script_path.chmod(0o644)
    output_dir = run_dir / "output"
    output_dir.mkdir()
    output_dir.chmod(0o777)  # the container's non-root user must be able to write here

    name = f"r-sandbox-{uuid.uuid4().hex[:12]}"
    create = [
        "docker", "create", "--name", name,
        "--network", "none",                                  # no network at all
        "--memory", memory, "--memory-swap", memory,          # memory cap, no swap
        "--cpus", "1", "--pids-limit", "256",                 # no fork bombs
        "--read-only", "--tmpfs", "/tmp:rw,size=256m",        # only /tmp is writable
        "--cap-drop", "ALL", "--security-opt", "no-new-privileges",
        "-e", f"SANDBOX_TIMEOUT={timeout_s}",
        "-v", f"{data_dir.resolve()}:/work/data/clean:ro",    # data is read-only
        "-v", f"{script_path}:/work/script.R:ro",
        "-v", f"{output_dir}:/work/output:rw",
        image,
    ]
    subprocess.run(create, check=True, capture_output=True, text=True)

    host_timed_out = False
    start = time.monotonic()
    try:
        try:
            proc = subprocess.run(
                ["docker", "start", "--attach", name],
                capture_output=True, text=True, timeout=timeout_s + _HOST_GRACE_S,
            )
            stdout, stderr = proc.stdout, proc.stderr
        except subprocess.TimeoutExpired as exc:
            # Backstop if the in-container limit somehow fails: kill from outside.
            host_timed_out = True
            subprocess.run(["docker", "kill", name], capture_output=True)
            stdout = (exc.stdout or b"").decode() if isinstance(exc.stdout, bytes) else (exc.stdout or "")
            stderr = (exc.stderr or b"").decode() if isinstance(exc.stderr, bytes) else (exc.stderr or "")
        duration = time.monotonic() - start

        inspect = subprocess.run(
            ["docker", "inspect", "--format", "{{json .State}}", name],
            check=True, capture_output=True, text=True,
        )
        state = json.loads(inspect.stdout)
    finally:
        subprocess.run(["docker", "rm", "--force", name], capture_output=True)

    exit_code = int(state.get("ExitCode", -1))
    plots = sorted(p for p in output_dir.rglob("*") if p.suffix.lower() in PLOT_SUFFIXES)
    return SandboxResult(
        stdout=stdout,
        stderr=stderr,
        exit_code=exit_code,
        timed_out=host_timed_out or exit_code == TIMEOUT_EXIT_CODE,
        oom_killed=bool(state.get("OOMKilled", False)),
        duration_s=round(duration, 2),
        output_dir=output_dir,
        plots=plots,
    )

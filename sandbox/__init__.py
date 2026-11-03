"""Execution sandbox: run untrusted R code in a locked-down Docker container."""

from sandbox.runner import IMAGE, SandboxResult, docker_available, image_available, run_r_script

__all__ = ["IMAGE", "SandboxResult", "docker_available", "image_available", "run_r_script"]

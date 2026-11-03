#!/bin/sh
# Entry point inside the sandbox container: run /work/script.R with a time limit.
#
# `timeout` sends SIGTERM after SANDBOX_TIMEOUT seconds and SIGKILL 5 seconds
# later if R is still running. It exits with code 124 when the limit was hit.
set -eu
exec timeout --signal=TERM --kill-after=5s "${SANDBOX_TIMEOUT:-30}s" \
    Rscript --vanilla /work/script.R

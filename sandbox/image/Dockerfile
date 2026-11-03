# R execution sandbox for agent-generated code.
#
# Same R version and packages as the project's renv.lock. Build from the repo
# root (the build needs renv.lock):
#   docker build -f sandbox/image/Dockerfile -t stats-agent-sandbox .
#
# The restrictions (no network, read-only data, time and memory limits) are
# applied when the container is started. See sandbox/runner.py.

FROM rocker/r-ver:4.6.1

# System libraries some R packages need if a prebuilt binary isn't available
# and they have to compile from source.
RUN apt-get update && apt-get install -y --no-install-recommends \
        cmake libcurl4-openssl-dev libssl-dev libxml2-dev \
        libfontconfig1-dev libfreetype6-dev libharfbuzz-dev libfribidi-dev \
        libpng-dev libjpeg-dev libtiff-dev libwebp-dev \
    && rm -rf /var/lib/apt/lists/*

# Install the exact package versions from renv.lock into a fixed library.
# Posit Package Manager serves prebuilt Linux binaries, which is much faster
# than compiling tidyverse and arrow from source.
ENV RENV_CONFIG_REPOS_OVERRIDE=https://p3m.dev/cran/__linux__/noble/latest \
    R_LIBS=/opt/r-lib
COPY renv.lock /opt/renv.lock
RUN R -q -e 'install.packages("renv", repos = Sys.getenv("RENV_CONFIG_REPOS_OVERRIDE"))' \
 && R -q -e 'renv::restore(lockfile = "/opt/renv.lock", library = "/opt/r-lib", prompt = FALSE)' \
 && R -q -e 'library(dplyr); library(arrow); library(janitor); library(readxl); cat("packages OK\n")'

# Run as an unprivileged user, never root.
RUN useradd --create-home --uid 10001 sandbox
COPY sandbox/image/run.sh /usr/local/bin/run-r-script
RUN chmod 0755 /usr/local/bin/run-r-script

USER sandbox
WORKDIR /work
ENTRYPOINT ["/usr/local/bin/run-r-script"]

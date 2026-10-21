# One-time R environment setup with renv.
# Run from the repo root:  Rscript setup_r.R
#
# R packages are declared in DESCRIPTION. If renv.lock exists, this restores
# the exact versions recorded there. Otherwise it sets up renv if needed
# (.Rprofile and renv/), installs the declared packages and writes renv.lock.
#
# On macOS with Homebrew R, packages compile from source. Some need these
# system libraries first:  brew install harfbuzz fribidi libtiff

CRAN <- "https://cloud.r-project.org"
options(repos = c(CRAN = CRAN))

if (!requireNamespace("renv", quietly = TRUE)) {
  install.packages("renv")
}

if (file.exists("renv.lock")) {
  renv::restore(prompt = FALSE)
} else {
  # An editor (RStudio, or VS Code's R extension) may already have set up
  # renv here. Only set it up if it isn't there yet.
  if (!file.exists("renv/activate.R")) {
    renv::init(bare = TRUE, restart = FALSE)
  }
  # "explicit": the lockfile records exactly what DESCRIPTION declares (plus
  # dependencies and renv itself), not whatever renv finds in the code.
  # Editor tooling installed into the same library (languageserver, styler,
  # ...) stays out.
  renv::settings$snapshot.type("explicit")
  renv::install(prompt = FALSE)
  renv::snapshot(prompt = FALSE)
}

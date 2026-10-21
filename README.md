# Stats Analyst Agent

An LLM agent that answers questions about NHS England statistics by writing and running R code against locally cached, cleaned datasets.

> 🚧 Work in progress. The data pipeline is in place; the agent is not built yet.

## Structure

```
.
├── R/
│   └── ingest_helpers.R           # shared helpers: scraping, downloads, row-count logging
├── data/                          # everything except data/ingest/ is gitignored
│   ├── ingest/                    # one script per dataset: download -> clean -> parquet
│   │   ├── rtt_incomplete_provider.R
│   │   └── ae_provider.R
│   ├── raw/                       # untouched downloads, one folder per dataset
│   └── clean/                     # tidy parquet, read by the agent
├── DESCRIPTION                    # declared R packages (renv reads this)
├── setup_r.R                      # one-time renv setup
├── renv.lock                      # pinned R packages (created by setup_r.R)
├── pyproject.toml / uv.lock       # Python environment (agent code goes here later)
└── .python-version
```

## Setup

You need R (4.3 or later) and [uv](https://docs.astral.sh/uv/). With Homebrew R, packages compile from source and need some system libraries first.

```sh
brew install harfbuzz fribidi libtiff   # macOS + Homebrew R only
Rscript setup_r.R   # restores renv.lock (tidyverse, arrow, janitor, readxl)
uv sync             # creates .venv (no dependencies yet)
```

## Refreshing the data

Run each ingest script from the repo root:

```sh
Rscript data/ingest/rtt_incomplete_provider.R
Rscript data/ingest/ae_provider.R
```

Each script finds the newest 24 months on NHS England's site and downloads any files that are not already in `data/raw/`. It writes one parquet file to `data/clean/` and prints a row count before and after every cleaning step. When rows are filtered or merged on purpose, the script says so and prints the counts. It never drops rows silently.

## Datasets

| File | Grain | Source |
|---|---|---|
| `data/clean/rtt_incomplete_provider.parquet` | month × provider × treatment function | [RTT waiting times](https://www.england.nhs.uk/statistics/statistical-work-areas/rtt-waiting-times/): full CSV extract, Part_2 (incomplete pathways) |
| `data/clean/ae_provider.parquet` | month × provider | [A&E attendances and emergency admissions](https://www.england.nhs.uk/statistics/statistical-work-areas/ae-waiting-times-and-activity/): monthly CSV |

Points to know before querying:

- **RTT:** rows with `treatment_function_code == "C_999"` (`is_all_specialties_total`) hold each provider's all-specialty total. To get provider totals, filter to these rows. Do not sum all the rows, because that counts every patient twice. `pct_within_18_weeks` leaves out patients whose clock start is unknown, which matches NHS England's measure.
- **A&E:** `pct_within_4hrs` covers all attendance types, booked appointments included (NHS England's headline measure). `pct_within_4hrs_type1` covers major A&E departments only. Providers with no attendances are kept and marked with `has_ae_activity = FALSE`.

## License

_TBD_

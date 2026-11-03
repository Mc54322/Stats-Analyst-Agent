# Reads one parquet file from the read-only data mount and prints its row count.
library(arrow)
ae <- read_parquet("data/clean/ae_provider.parquet")
cat("rows:", nrow(ae), "\n")

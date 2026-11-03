# Tries to reach the internet. Inside the sandbox this must fail.
con <- url("https://www.england.nhs.uk/")
first_line <- readLines(con, n = 1, warn = FALSE)
close(con)
cat("NETWORK REACHABLE\n")

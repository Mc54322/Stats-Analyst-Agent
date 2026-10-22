# Data notes: gotchas that cause wrong answers

Data as downloaded 21 Oct 2026. Always state the "as of" month in answers.

## Both datasets

- **Different months.** RTT covers Sep 2024 – Aug 2026; A&E covers Oct 2024 – Sep 2026.
  The "latest month" differs between them: Aug 2026 for RTT, Sep 2026 for A&E.
- **`period` means different things.** RTT is a snapshot of the waiting list at
  month end. A&E is activity during the month. Both are stored as the 1st of the month.
- **Percentages: always use the ratio of sums, never `mean()` of the `pct_*` columns.**
  Averaging overweights small providers (RTT 18-week: 77.2% wrong vs 65.2% right;
  A&E 4-hour: 80.6% wrong vs 74.4% right).
- **Group by code, not by name.** Provider names change (18 RTT codes, 11 A&E codes).
  Show the latest name for each code.
- **Joining RTT to A&E loses providers.** Only 136 of the 191 A&E codes appear in RTT.
  Use `left_join` and report what didn't match.
- **NHS trust vs other providers:** a 3-character ODS code starting with R or T
  (`grepl("^[RT][A-Z0-9]{2}$", code)`). Longer codes, including ones starting with
  R or T, are independent-sector or other sites.

## RTT (`rtt_incomplete_provider.parquet`)

- **Grain:** month × provider × treatment function.
- **`C_999` ("Total") rows sit next to the specialty rows.** For provider or national
  totals, filter `is_all_specialties_total == TRUE`. For specialties, filter `FALSE`.
  Never sum both; that doubles the count.
- **X02–X06 ("Other - …") are real specialty groups, not subtotals.** They hold
  22% of pathways. A specialty with no row of its own (e.g. paediatric cardiology)
  is inside one of them, so don't say it has no waits.
- **`over_*_weeks` columns are cumulative.** `over_52_weeks` includes `over_65_weeks`.
  For a band, subtract: 52–65 weeks = `over_52_weeks - over_65_weeks`.
- **Counts are pathways, not patients.** One patient can have several pathways.
  Say "7.2 million pathways", not "7.2 million people".
- **Includes `NONC` (non-English commissioners), which NHS England excludes from all
  published figures.** National totals here are about 31k higher than published
  (Aug 2026: 7,189,213 vs 7,158,164). Over-104-week counts are most affected
  (544 vs 220 published).
- **National totals are "reported", not NHS England's headline "with estimates".**
  Non-submitting trusts are simply missing. Published Aug 2026 with estimates
  is 7,370,100.
  - Sheffield (RHQ, ~97k) is missing from Jul 2025 onwards.
  - Barking, Havering & Redbridge (RF4, ~72k) is missing Nov 2025.
  - A month-on-month drop may be a gap in submissions, not a real fall. Check the
    provider count per month.
- **Mergers break provider time series.**
  - North Bristol (RVJ) merged into RA7 from Jul 2026; RA7 jumps from 51k to 96k.
  - North Middlesex (RAP) merged into Royal Free (RAL) from Jan 2025.
  - Don't report these as real changes.
- **More providers over time** (457 to 532 a month), mostly independent sector.
  NHS trusts actually fell (155 to 145, through mergers). Non-trust providers are
  73% of providers but hold only 6.6% of the waiting list. Limit rankings to NHS
  trusts unless asked otherwise.
- **`provider_parent_*` is the ICB, not the region.** ICBs merged in Apr 2026:
  42 up to Mar 2026, 36 from Apr 2026, 48 codes in all. ICB trends break at Apr 2026.
- **`unknown_clock_start` is always 0.** Ignore it.

## A&E (`ae_provider.parquet`)

- **Grain:** month × provider. Matches NHS England's published national figures exactly.
- **Two different 4-hour measures:**
  - Headline (all types, incl. booked) is `pct_within_4hrs`: 74.4% in Sep 2026.
  - Major A&E only is `pct_within_4hrs_type1`: 60.6%.
  - Say which one you're quoting.
- **Many providers aren't hospitals** (walk-in centres, UTCs, or no attendances at all,
  where `has_ae_activity == FALSE` and `pct_*` is NA). To rank hospitals, filter
  `attendances_type1_all > 0`.
- **`dta_wait_over_12hrs` is measured from the decision to admit, not from arrival.**
  These are "trolley waits" (50,582 in Sep 2026). 12 hours from arrival is NOT in
  this data; it's in NHS England's separate ECDS supplementary analysis.
- **`emergency_admissions_total` includes admissions that didn't come through A&E.**
  For A&E conversion rates use `emergency_admissions_via_ae / attendances_total`.

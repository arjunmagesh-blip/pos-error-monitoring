---
name: pos-error-collector
description: Collect a daily snapshot of POS order outcomes (success/failed with error codes) from BigQuery and save it as a local CSV. Use to capture one day (or a date range) of failed-order data for later spike analysis. Triggers - "collect pos errors", "snapshot failed orders", "pull yesterday's errors", "run the daily error collection".
---

# POS Error Daily Collector

Runs the failed-orders query against BigQuery (read-only) for a given day,
aggregates it, and writes one CSV per day to `~/posdata/error_snapshots/`.
The companion skill **pos-error-spike-analyzer** reads those CSVs.

## What it stores (grain)

One row per `snapshot_date x pos_partner x integration_type x system x merchant x result x status_code`:

| column | meaning |
|---|---|
| snapshot_date | order created_date (the day) |
| pos_partner | integration name (GPOS, EPOINT, …) |
| integration_type, system | integration_type id; CMS vs ECMS |
| merchant_key, merchant_name, brand_name, account_name, country | merchant identity |
| result | SUCCESS or FAILED |
| status_code | error code (FAILED only; NULL for SUCCESS) |
| sample_message | one example error message for that group (FAILED only) |
| order_count | number of orders in the group |

`order_count` lets you derive both failed counts and failure % (failed / total).

## Prerequisites

- `gcloud` authenticated (`gcloud auth list` shows the account) and project = `tabsquare-data-sciences`.
- Source data is in **asia-southeast1** — every `bq` call MUST pass `--location=asia-southeast1`.
- Files live in `~/posdata/error_snapshots/` (create if missing).

## Procedure

1. **Pick the date(s).** Default = yesterday. Accept an explicit date or a
   range from the user. The query bounds BOTH `created_date` and `changed_date`
   to the same day (mirrors the established analyst query) — collect one day at
   a time so each file is a clean single-day snapshot and re-runs are idempotent.

2. **For each date `D` (format YYYY-MM-DD):** substitute placeholders in
   `snapshot_query.sql` and run, writing CSV:

   ```bash
   SKILL=~/posdata/.claude/skills/pos-error-collector
   OUT=~/posdata/error_snapshots
   D=2026-06-17                       # the target day
   sed "s/{{START_DATE}}/$D/g; s/{{END_DATE}}/$D/g" "$SKILL/snapshot_query.sql" > /tmp/snap_$D.sql
   bq query --use_legacy_sql=false --location=asia-southeast1 \
       --format=csv --max_rows=1000000 < /tmp/snap_$D.sql > "$OUT/pos_errors_$D.csv"
   ```

   To compute "yesterday" portably:
   `D=$(python3 -c "import datetime;print(datetime.date.today()-datetime.timedelta(days=1))")`

3. **Verify** the file is non-empty and report a quick summary:

   ```bash
   wc -l "$OUT/pos_errors_$D.csv"
   # failed rows / total orders for the day:
   awk -F, 'NR>1{t+=$NF; if($10=="FAILED") f+=$NF} END{printf "failed=%d total=%d (%.2f%%)\n",f,t,(t?f/t*100:0)}' "$OUT/pos_errors_$D.csv"
   ```

   (Column 10 = `result`, last column = `order_count`. If a `sample_message`
   contains a comma the awk check may be off — trust the BQ run; awk is just a sanity peek.)

4. **Report** to the user: date collected, file path, failed/total counts.

## Notes & gotchas

- **Idempotent:** re-running a date overwrites `pos_errors_<date>.csv`.
- **Cost:** ~140 MB scanned per day.
- A day created late whose status changes the next day is excluded (both date
  filters bound to the same day) — consistent with the source dashboard.
- This skill is READ-ONLY against BigQuery (no BQ writes — we don't have write access).
- To backfill, loop dates: `for D in 2026-06-11 2026-06-12 ...; do ...; done`.
- The heavy `pos_partner` CASE mapping and merchant joins live inside
  `snapshot_query.sql`; if POS partner IDs change, update that file.

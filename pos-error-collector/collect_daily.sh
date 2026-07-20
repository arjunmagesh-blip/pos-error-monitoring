#!/bin/zsh
# Standalone daily collector for POS error snapshots.
# Runs the read-only failed-orders query for YESTERDAY and writes a CSV.
# Safe to run from launchd/cron (uses the logged-in gcloud user's credentials).
# Manual use:  ./collect_daily.sh [YYYY-MM-DD]   (defaults to yesterday)

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

SKILL="$HOME/posdata/.claude/skills/pos-error-collector"
OUT="$HOME/posdata/error_snapshots"
LOG="$OUT/collector.log"
mkdir -p "$OUT"

# Desktop notification (best-effort; no-op if osascript is unavailable).
notify() {
  /usr/bin/osascript -e "display notification \"$1\" with title \"POS Error Collector\"" 2>/dev/null
}

# Portable timeout wrapper (macOS has no `timeout`/`gtimeout`).
# Backgrounds the command, and a watchdog kills it — and its children, e.g. the
# python process under the `bq` shell wrapper — if it overruns. Returns the
# command's exit code (non-zero if killed), so the caller's error path fires.
run_with_timeout() {
  local secs="$1"; shift
  "$@" &
  local pid=$!
  (
    sleep "$secs"
    if kill -0 "$pid" 2>/dev/null; then
      echo "[$(date '+%Y-%m-%d %H:%M:%S')] !!! TIMEOUT after ${secs}s — killing pid $pid" >> "$LOG"
      pkill -P "$pid" 2>/dev/null; kill -TERM "$pid" 2>/dev/null
      sleep 3
      pkill -9 -P "$pid" 2>/dev/null; kill -KILL "$pid" 2>/dev/null
    fi
  ) &
  local watcher=$!
  wait "$pid"; local rc=$?
  kill "$watcher" 2>/dev/null; wait "$watcher" 2>/dev/null
  return $rc
}

# Target date: arg 1 if given, else yesterday.
if [ -n "$1" ]; then
  D="$1"
else
  D=$(python3 -c "import datetime;print(datetime.date.today()-datetime.timedelta(days=1))")
fi

echo "[$(date '+%Y-%m-%d %H:%M:%S')] START collect $D" >> "$LOG"

# --- Auth precheck: refresh token must still be valid ---
if ! run_with_timeout 120 gcloud auth print-access-token >/dev/null 2>>"$LOG"; then
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] !!! AUTH FAILED for $D — run: gcloud auth login" >> "$LOG"
  notify "AUTH FAILED — run 'gcloud auth login'. $D was not collected."
  exit 1
fi

SQL="/tmp/pos_snap_$D.sql"
sed "s/{{START_DATE}}/$D/g; s/{{END_DATE}}/$D/g" "$SKILL/snapshot_query.sql" > "$SQL"

# Query with retries. Observed timeouts are transient (successful runs take ~6s),
# so a short retry clears them. Critically, never leave a 0-byte/partial file
# behind: a poison empty file reads downstream as "collected, no data" and the
# day vanishes silently from the spike analyzer's window (this is exactly how the
# 2026-07-06 XILNEX spike went undetected).
CSV="$OUT/pos_errors_$D.csv"
MAX_TRIES=3
rc=1
for try in $(seq 1 $MAX_TRIES); do
  if run_with_timeout 600 bq query --use_legacy_sql=false --location=asia-southeast1 \
        --format=csv --max_rows=1000000 < "$SQL" > "$CSV" 2>>"$LOG"; then
    rc=0; break
  fi
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARN $D query attempt $try/$MAX_TRIES failed" >> "$LOG"
  [ "$try" -lt "$MAX_TRIES" ] && sleep 15
done

if [ "$rc" -eq 0 ]; then
  rows=$(( $(wc -l < "$CSV") - 1 ))
  if [ "$rows" -lt 1 ]; then
    # Succeeded but no data (header-only). POS traffic is never truly zero, so
    # treat this as a bad collection: remove the file so the day shows as MISSING
    # (loudly flagged by the analyzer) rather than silently empty.
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARN $D produced $rows rows — removing file so it is not treated as collected" >> "$LOG"
    rm -f "$CSV"
    notify "WARNING — $D produced $rows rows (file removed). Check collector.log."
  else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] OK    $D -> $rows rows" >> "$LOG"
  fi
  rm -f "$SQL"
else
  # All attempts failed — delete the 0-byte/partial file the redirect created.
  rm -f "$CSV"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] !!! ERROR $D query failed after $MAX_TRIES attempts (empty file removed). If auth-related, run: gcloud auth login" >> "$LOG"
  notify "Query FAILED for $D after $MAX_TRIES tries. Check collector.log (may need 'gcloud auth login')."
  exit 1
fi

# --- Rebuild the Menu Error dashboard HTML from the latest snapshots ---
# Regenerates ~/posdata/dashboard/menu-errors.html locally. To push the new
# data to the shared claude.ai artifact, do the manual nudge (see dashboard/README).
DASH="$HOME/posdata/dashboard"
if [ -f "$DASH/build_dashboard.py" ]; then
  if python3 "$DASH/build_dashboard.py" >> "$LOG" 2>&1; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] OK    dashboard rebuilt" >> "$LOG"
  else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARN  dashboard build failed (see log above)" >> "$LOG"
    notify "Dashboard build failed for $D. Check collector.log."
  fi
fi

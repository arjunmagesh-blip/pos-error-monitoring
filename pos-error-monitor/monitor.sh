#!/bin/zsh
# Hourly POS error ACTIVE MONITOR.
# Runs the rolling-window failed-orders query, evaluates it against thresholds,
# and posts alerts to Slack for NEW / ESCALATED / ONGOING / RESOLVED conditions.
# Read-only BigQuery (uses the logged-in gcloud user's credentials).
# Manual use:  ./monitor.sh            (normal run)
#              ./monitor.sh --dry-run  (query + evaluate, print payload, DON'T post, DON'T touch state)

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

SKILL="$HOME/posdata/.claude/skills/pos-error-monitor"
OUT="$HOME/posdata/error_snapshots"
LOG="$OUT/monitor.log"
STATE="$SKILL/state.json"
WEBHOOK_FILE="$SKILL/slack_webhook.txt"
mkdir -p "$OUT"

DRY=0
[ "$1" = "--dry-run" ] && DRY=1

ts() { date '+%Y-%m-%d %H:%M:%S'; }
notify() { /usr/bin/osascript -e "display notification \"$1\" with title \"POS Error Monitor\"" 2>/dev/null; }

# Portable timeout wrapper (macOS has no `timeout`).
run_with_timeout() {
  local secs="$1"; shift
  "$@" &
  local pid=$!
  ( sleep "$secs"
    if kill -0 "$pid" 2>/dev/null; then
      echo "[$(ts)] !!! TIMEOUT after ${secs}s — killing pid $pid" >> "$LOG"
      pkill -P "$pid" 2>/dev/null; kill -TERM "$pid" 2>/dev/null
      sleep 3; pkill -9 -P "$pid" 2>/dev/null; kill -KILL "$pid" 2>/dev/null
    fi ) &
  local watcher=$!
  wait "$pid"; local rc=$?
  kill "$watcher" 2>/dev/null; wait "$watcher" 2>/dev/null
  return $rc
}

echo "[$(ts)] START monitor (dry=$DRY)" >> "$LOG"

# --- Auth precheck ---
if ! run_with_timeout 120 gcloud auth print-access-token >/dev/null 2>>"$LOG"; then
  echo "[$(ts)] !!! AUTH FAILED — run: gcloud auth login" >> "$LOG"
  notify "AUTH FAILED — run 'gcloud auth login'. Monitor did not run."
  exit 1
fi

# --- Window hours from thresholds.json (default 4) ---
WH=$(python3 -c "import json;print(json.load(open('$SKILL/thresholds.json')).get('window_hours',4))" 2>/dev/null)
[ -z "$WH" ] && WH=4

# --- Refresh per-integration baselines from the daily snapshots (cheap; used by
#     the shadow baseline-deviation tier in evaluate.py). ---
BLDAYS=$(python3 -c "import json;print(json.load(open('$SKILL/thresholds.json')).get('baseline',{}).get('baseline_days',14))" 2>/dev/null)
[ -z "$BLDAYS" ] && BLDAYS=14
python3 "$SKILL/build_baselines.py" --dir "$OUT" --out "$SKILL/baselines.json" --days "$BLDAYS" >> "$LOG" 2>&1 \
  || echo "[$(ts)] WARN baseline build failed (baseline tier will be skipped)" >> "$LOG"

SQL="/tmp/pos_monitor.sql"
CSV="/tmp/pos_monitor_window.csv"
sed "s/{{WINDOW_HOURS}}/$WH/g" "$SKILL/monitor_query.sql" > "$SQL"

if ! run_with_timeout 300 bq query --use_legacy_sql=false --location=asia-southeast1 \
      --format=csv --max_rows=1000000 < "$SQL" > "$CSV" 2>>"$LOG"; then
  echo "[$(ts)] !!! ERROR query failed (see log). If auth-related, run: gcloud auth login" >> "$LOG"
  notify "Monitor query FAILED. Check monitor.log."
  exit 1
fi

rows=$(( $(wc -l < "$CSV") - 1 ))
echo "[$(ts)] window=${WH}h rows=$rows" >> "$LOG"
if [ "$rows" -lt 1 ]; then
  echo "[$(ts)] WARN 0 rows in window — skipping evaluation" >> "$LOG"
  exit 0
fi

# --- Evaluate. In dry-run, use a throwaway state copy so real state is untouched. ---
EVAL_STATE="$STATE"
if [ "$DRY" -eq 1 ]; then
  EVAL_STATE="/tmp/pos_monitor_state_dry.json"
  cp "$STATE" "$EVAL_STATE" 2>/dev/null || echo '{}' > "$EVAL_STATE"
fi

PAYLOAD=$(python3 "$SKILL/evaluate.py" "$CSV" "$SKILL/thresholds.json" "$EVAL_STATE" 2>>"$LOG")
rc=$?
if [ "$rc" -ne 0 ]; then
  echo "[$(ts)] !!! evaluate.py exited $rc" >> "$LOG"
  exit 1
fi

if [ -z "$PAYLOAD" ]; then
  echo "[$(ts)] OK    no alert changes" >> "$LOG"
  exit 0
fi

if [ "$DRY" -eq 1 ]; then
  echo "[$(ts)] DRY-RUN payload (not posted):" >> "$LOG"
  echo "$PAYLOAD"
  exit 0
fi

# --- Post to Slack ---
if [ ! -s "$WEBHOOK_FILE" ] || grep -q "PASTE_YOUR" "$WEBHOOK_FILE"; then
  echo "[$(ts)] WARN alerts present but no Slack webhook configured ($WEBHOOK_FILE)" >> "$LOG"
  notify "POS alert fired but Slack webhook not set. See monitor.log."
  echo "$PAYLOAD" >> "$OUT/monitor_unsent_alerts.log"
  exit 0
fi
WEBHOOK=$(head -1 "$WEBHOOK_FILE" | tr -d '[:space:]')

HTTP=$(curl -s -o /tmp/pos_monitor_slack.out -w "%{http_code}" -X POST \
  -H 'Content-type: application/json' --data "$PAYLOAD" "$WEBHOOK" 2>>"$LOG")
if [ "$HTTP" = "200" ]; then
  echo "[$(ts)] OK    posted alerts to Slack" >> "$LOG"
else
  echo "[$(ts)] !!! Slack post failed http=$HTTP $(cat /tmp/pos_monitor_slack.out 2>/dev/null)" >> "$LOG"
  notify "POS alert Slack post failed (http $HTTP). Check monitor.log."
fi

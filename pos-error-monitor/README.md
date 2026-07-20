# POS Error Active Monitor

Hourly watchdog over live POS order outcomes. Complements the once-a-day
`pos-error-collector` (which snapshots yesterday for the dashboard) by catching
problems *as they happen* and pushing alerts to Slack.

## How it works
1. `monitor.sh` runs hourly (launchd, 07:00–23:00 SGT).
2. It runs `monitor_query.sql` over a rolling window (`window_hours` in
   `thresholds.json`, default 4h) on `created_date` — read-only BigQuery,
   `asia-southeast1`, logged-in gcloud user's creds.
3. `evaluate.py` applies tiered thresholds and diffs against `state.json`.
4. New / escalated / still-ongoing / resolved conditions post to Slack
   (webhook in `slack_webhook.txt`). `state.json` dedupes so an ongoing
   incident re-notifies at most every `renotify_hours` (default 6h).

**Detection latency ≈ 1.5–2.5h**: the CDC source lags real time by ~1.5h.

## Thresholds (`thresholds.json`)
Derived from ~2 weeks of snapshots (baseline ~0.5% fail, ~0.13% timeout).
Edit the file — the next hourly run picks it up, no reload needed.

| Scope | min orders | ⚠️ warn | 🔴 critical |
|---|---|---|---|
| system-wide | 1000 | fail 1.5% / to 0.8% | fail 3% / to 1.5% |
| integration | 150 | fail 4% / to 2.5% | fail 8% / to 5% |
| merchant | 25 | fail 30% / to 15% | fail 50% / to 30% |

`min orders` = volume floor in the window; below it the scope is ignored
(kills small-sample noise). Timeout = status_code 504.

## Manual use
```
./monitor.sh            # normal run (queries, evaluates, posts to Slack)
./monitor.sh --dry-run  # queries + evaluates, prints payload, DOES NOT post
                        # and DOES NOT touch state.json
```

## Files
- `monitor.sh` — orchestrator (auth check, query, evaluate, Slack post)
- `monitor_query.sql` — rolling-window aggregated query (`{{WINDOW_HOURS}}`)
- `evaluate.py` — threshold logic + state dedupe + Slack Block Kit builder
- `thresholds.json` — tunable thresholds & window
- `slack_webhook.txt` — Slack incoming-webhook URL (chmod 600)
- `state.json` — active-alert state (auto-managed; `{}` = all clear)

## Logs
`~/posdata/error_snapshots/monitor.log` (app), `monitor.launchd.{out,err}.log`
(launchd). If an alert fires but no webhook is set, the payload is appended to
`monitor_unsent_alerts.log` and a desktop notification fires.

## launchd
`~/Library/LaunchAgents/com.tabsquare.pos-error-monitor.plist`
```
launchctl unload ~/Library/LaunchAgents/com.tabsquare.pos-error-monitor.plist
launchctl load   ~/Library/LaunchAgents/com.tabsquare.pos-error-monitor.plist
```
Reload after editing the plist (e.g. changing run hours). Editing
`thresholds.json` needs no reload.

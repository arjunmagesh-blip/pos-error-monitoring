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

**Sleep and missed runs.** The whole run holds a `caffeinate -i` assertion so
the Mac can't idle-sleep mid-query. It cannot stop lid-close sleep, so after
missed runs the next run logs `COVERAGE GAP` (plus a desktop notification) and
widens its window to cover the missed hours (max 12h). `last_success` holds
the epoch time of the last completed non-dry run.

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

**Near-outage (merchant):** low-volume outlets rarely reach 25 orders in a
window, so a near-total outage could slip under the floor (6 Oct 2026: 75/78
failing all day, no alert). `merchant.near_outage` fires 🔴 critical when
fails >= 12 AND fail rate >= 80%, ignoring `min orders`. Backtest over
23 Sep-6 Oct 2026: ~1 extra incident/day, all 82-100% failing, no chronic
repeaters. Slack shows these as `MERCHANT · NEAR-OUTAGE`.

**Baseline deviation (integration):** see the `baseline` block in
`thresholds.json` (partner fail rate vs its own 14-day baseline).

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
- `last_success` — epoch of last completed run (drives gap catch-up)

## Logs
`~/posdata/error_snapshots/monitor.log` (app), `monitor.launchd.{out,err}.log`
(launchd). Every alert event is logged as an `[alert] ...` line (kind, level,
scope, name, rate, counts) just before the Slack post result. If an alert fires but no webhook is set, the payload is appended to
`monitor_unsent_alerts.log` and a desktop notification fires.

## launchd
`~/Library/LaunchAgents/com.tabsquare.pos-error-monitor.plist`
```
launchctl unload ~/Library/LaunchAgents/com.tabsquare.pos-error-monitor.plist
launchctl load   ~/Library/LaunchAgents/com.tabsquare.pos-error-monitor.plist
```
Reload after editing the plist (e.g. changing run hours). Editing
`thresholds.json` needs no reload.

# POS Error Monitoring

Near-real-time and daily monitoring of **POS order failures** — orders TabSquare sends to a
partner POS (XILNEX, RAPTOR, GPOS, Simphony, …) that come back `FAILED` (including timeouts).
Read-only over BigQuery (`tabsquare-data-sciences`, region `asia-southeast1`).

This repo is the **reference implementation** currently running on a laptop via `launchd`.
The intended production build-out is specified in [`docs/pos-error-monitor-spec.md`](docs/pos-error-monitor-spec.md).

## What's here

| Folder | What it does |
|---|---|
| [`pos-error-monitor/`](pos-error-monitor/) | **Hourly** watchdog. Runs a rolling 4h window query, applies tiered thresholds, and posts spike alerts to Slack. See its [README](pos-error-monitor/README.md). |
| [`pos-error-collector/`](pos-error-collector/) | **Daily** snapshot of the prior day's order outcomes to CSV — feeds the dashboard and supplies the per-partner baselines the monitor uses. |
| [`docs/`](docs/) | Engineering specification for productionizing this. |

## Detection tiers (monitor)

Four independent checks per window — three absolute, one relative:

| Tier | Grain | Volume floor | Warn (fail / timeout) | Critical (fail / timeout) |
|---|---|---|---|---|
| System-wide | all traffic | 1,000 | 1.5% / 0.8% | 3% / 1.5% |
| Integration | POS partner | 150 | 4% / 2.5% | 8% / 5% |
| Merchant | store | 25 | 30% / 15% | 50% / 30% |
| Baseline-deviation | POS partner | ≥30 fails | fires at ≥2× the partner's own 14-day baseline **and** ≥ baseline + 3σ | — |

A **timeout** = POS status code `504`. Thresholds live in `pos-error-monitor/thresholds.json`.

## Setup / running locally

1. **Auth:** the scripts use the logged-in `gcloud` user's credentials (read-only BigQuery).
2. **Slack webhook (secret — not in this repo):** create `pos-error-monitor/slack_webhook.txt`
   containing your Slack incoming-webhook URL. Copy the template:
   ```
   cp pos-error-monitor/slack_webhook.txt.example pos-error-monitor/slack_webhook.txt
   # then paste the real URL and: chmod 600 pos-error-monitor/slack_webhook.txt
   ```
3. **Test without posting:** `./pos-error-monitor/monitor.sh --dry-run`
4. **Schedule:** on the reference machine, `launchd` runs `monitor.sh` hourly (07:00–23:00 SGT)
   and `collect_daily.sh` once at 09:00.

## Not committed (by design)

`slack_webhook.txt` (secret) and the runtime artifacts `state.json`, `baselines.json`,
`baseline_shadow.log`, logs, and `*.csv` snapshots — all auto-generated and containing live
operational data. See `.gitignore`.

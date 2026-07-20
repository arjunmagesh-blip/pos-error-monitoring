# POS Error Monitoring — Engineering Specification (Build-Out)

**Status:** Draft for engineering review
**Audience:** Platform / Data Engineering
**Purpose:** Productionize the existing POS error-monitoring prototype into a resilient, always-on service.

---

## 1. Overview

We detect and alert on abnormal **POS order failures** — orders TabSquare sends to a
partner POS (XILNEX, RAPTOR, GPOS, Simphony, …) that come back `FAILED` (including
timeouts). A working **reference implementation** already runs on a single laptop via
`launchd`; this spec defines the behavior to preserve and the production system to build.

### 1.1 Goals
- Detect POS failure/timeout **spikes** in near-real-time, at multiple granularities (platform, POS partner, merchant).
- Alert the right people via Slack (and on-call for severe incidents) with low noise.
- Run **24/7** with no single point of failure and self-monitoring.
- Keep detection logic tunable and **auditable**, with history for precision/recall analysis.

### 1.2 Non-goals
- Root-causing failures automatically (we surface the driving error code/message; humans triage).
- Replacing the existing daily **dashboard** (it can be re-pointed at the new data store later).
- Building a general-purpose observability platform — this is scoped to POS order outcomes.

---

## 2. Reference implementation (behavioral contract)

The prototype is the source of truth for *what to detect*. Preserve this behavior unless a
section below explicitly supersedes it.

| Component | Role | Cadence |
|---|---|---|
| `pos-error-collector` (`collect_daily.sh`) | Daily snapshot of prior day → CSV | 09:00 SGT daily |
| `pos-error-spike-analyzer` (`analyze_spikes.py`) | Day-over-day mean+2σ spike report over snapshots | On demand / daily |
| `pos-error-monitor` (`monitor.sh` → `evaluate.py`) | Hourly rolling-window threshold check → Slack | Hourly, 07:00–23:00 SGT |
| `build_baselines.py` | Per-partner baseline from snapshots | Each monitor run |

Data lives in local CSVs (`~/posdata/error_snapshots/`) and JSON (`thresholds.json`,
`baselines.json`, `state.json`). Alerts go to a Slack incoming webhook.

---

## 3. Data definitions (canonical — MUST be shared by all tiers)

These definitions currently live inside SQL/Python; the build-out MUST centralize them.

- **Source:** BigQuery project `tabsquare-data-sciences`, region `asia-southeast1`.
  - `all_skipque_cdc_data_prod.all_order_pos_status_view_prod` — **row per POS attempt** (not per order).
  - `all_skipque_cdc_data_prod.all_orders_view_prod`, `…all_organization_view_prod`
  - `tabsquare_dw_lookups.master_merchant_list` — merchant metadata.
- **Order outcome:** `Result` — `FAILED` vs success. A **fail** = an order whose outcome is `FAILED`.
- **Timeout:** a fail with `status_code = 504`. (⚠️ improvement candidate — see §7.11.)
- **Retry over-count:** because the status view is per-attempt, `COUNT(*)` over-counts failed
  *orders* by ~6% vs `COUNT(DISTINCT order_id)`. **Canonical metric MUST be distinct-order-based**
  (the dashboard already is; the monitor currently is not — align them).
- **Test/demo exclusion:** exclude `org.is_test_account = 1` (lives on the *organization* view, not
  the merchant list) **and** name patterns (`%test%`, `%demo%`, `%ts cafe%`, `%latest%`). ⚠️ brittle —
  replace with a maintained flag (see §7.10).
- **POS partner naming:** `pos_partner_id → name` is currently a hardcoded `CASE` (60+ branches) in SQL.
  MUST become a maintained **dimension table**.
- **Timestamp basis:** windows filter on `created_date` (UTC). Note the source feed lag in §6.1.

---

## 4. Functional requirements — detection

Four independent detection tiers evaluate the same window. Preserve semantics; §7 proposes
statistically stronger replacements the team may adopt.

### 4.1 Metrics per scope
For any scope in a window: `total`, `fails`, `timeouts` →
`fail_rate = fails/total`, `timeout_rate = timeouts/total`. Note `timeouts ⊆ fails`.

### 4.2 Severity resolution (fixed priority; first match wins, and names the "driver")
1. `fail_rate ≥ critical.fail` → **critical** (driver: fail)
2. `timeout_rate ≥ critical.timeout` → **critical** (driver: timeout)
3. `fail_rate ≥ warn.fail` → **warn** (driver: fail)
4. `timeout_rate ≥ warn.timeout` → **warn** (driver: timeout)
5. else → no alert

### 4.3 Tiers, volume floors, thresholds (current values)
A scope is skipped if `total < min_orders` (noise floor).

| Tier | Grain | Volume floor | Warn (fail / timeout) | Critical (fail / timeout) |
|---|---|---|---|---|
| System-wide | all traffic | 1,000 | 1.5% / 0.8% | 3% / 1.5% |
| Integration | POS partner | 150 | 4% / 2.5% | 8% / 5% |
| Merchant | store | 25 | 30% / 15% | 50% / 30% |
| Baseline-deviation | POS partner | ≥30 **fails** | *(relative — see 4.4)* | — |

Thresholds were derived from ~2 weeks of data (system baseline ≈ 0.5% fail / 0.13% timeout).

### 4.4 Baseline-deviation tier (relative)
Fires for a partner when **all** hold:
- `fails ≥ min_fails` (30)
- `fail_rate ≥ min_ratio × baseline_mean` (2×)
- `fail_rate ≥ baseline_mean + sigma × baseline_std` (3σ)

`baseline_mean/std` = mean & stdev of the partner's **daily** fail_rate over the trailing **14 days**.
Rationale: catches a partner surging above *its own* norm while still under the flat integration
floor (the XILNEX 0.5%-vs-0.09% case). ⚠️ grain mismatch (daily baseline vs sub-day window) — §7.3.

### 4.5 Window
Rolling **4h** (`window_hours`), evaluated hourly. Test/demo excluded. Aggregated per
`(pos_partner, merchant)`.

---

## 5. Functional requirements — alerting

### 5.1 Alert lifecycle (preserve)
Each alert has a stable ID (`scope::key`) and a state machine:
`NEW` → `ESCALATED` (warn→critical) → `ONGOING` (re-notify) → `RESOLVED` (no longer present).

### 5.2 Deduplication / re-notify (preserve)
- An ongoing incident re-notifies **at most every `renotify_hours`** (6h).
- One message on first fire; one on escalation; periodic while ongoing; one on resolve.

### 5.3 Slack payload (preserve, then enhance — §7.7)
Grouped Block Kit message: severity emoji, kind, scope, entity name, driver metric + rate over
window, `fails/timeouts/total` counts, sample error message (merchant scope), and for baseline
alerts the `N× baseline` context.

---

## 6. Current limitations (why we're building this out)

| # | Limitation | Impact |
|---|---|---|
| L1 | Runs on one laptop via `launchd`; sleeps/reboots stop it. | Silent outage of the monitor itself. |
| L2 | Active only 07:00–23:00 SGT. | **Overnight blind spot**; incidents surface at 07:00. |
| L3 | gcloud **user** creds; token expiry aborts runs. | Fragile auth, manual `gcloud auth login`. |
| L4 | Detection lag ~1.5–2.5h (CDC source lags ~1.5h). | Not real-time. |
| L5 | Baselines are **daily**-grain but window is 4h. | Variance mismatch → borderline/false detections. |
| L6 | **Flat** thresholds; no time-of-day / day-of-week seasonality. | Lunch-rush normal ≠ 3am normal; noise or misses. |
| L7 | State & data in local CSV/JSON. | No durability, no history, poison 0-byte files. |
| L8 | Independent alerts per scope; no correlation. | One vendor outage → many messages, no blast-radius. |
| L9 | Slack **webhook** only; no routing/ack/on-call. | No ownership, no escalation, no ack/resolve. |
| L10 | Hardcoded partner `CASE`; `%test%` string exclusion. | Brittle, drifts from reality. |
| L11 | Monitor query has no retry; small-sample rate FPs at merchant grain. | Lost cycles; noise. |

---

## 7. Proposed production design & improvements

Legend: **[R]** required to reach parity + resilience · **[E]** enhancement worth doing.

### 7.1 Compute & scheduling **[R]** (fixes L1, L2)
- Run in the cloud: **Cloud Run Job + Cloud Scheduler** (or Airflow/Composer if a DAG already exists).
- **24/7** evaluation. Keep a configurable "quiet routing" (e.g. overnight → low-severity channel,
  page only on critical) instead of *not running*.
- Evaluation cadence configurable; default every **15 min** (see latency §7.2).

### 7.2 Latency **[E]** (fixes L4)
- The ~1.5h floor is a property of the **source CDC view**, not our code. Work with Data Platform to
  identify a **lower-latency source** (streaming Pub/Sub of POS attempts, or a fresher table). If
  available, evaluate on a micro-batch (1–5 min) for minutes-level detection.
- If not available near-term: **document the lag as a known floor**, and align cadence to it (no point
  polling every minute against a 90-min-stale source).

### 7.3 Seasonal, robust baselines **[E]** (fixes L5, L6)
- Compute baselines on windows of the **same size** as evaluation.
- Bucket by **(partner, hour-of-day, day-of-week)** so "normal" reflects traffic shape.
- Use **robust statistics** (median + MAD, or trimmed mean) so the spikes we detect don't poison the
  baseline; exclude previously-alerted windows from baseline computation.
- Recompute nightly in BigQuery; store as a versioned baselines table.

### 7.4 Principled rate detection **[E]** (fixes L11, unifies floors+thresholds)
- Model fails as **binomial**; alert on statistical significance of observed rate vs expected baseline
  rate given `n` (one-sided test on proportions, or Bayesian rate with a credible interval).
- This subsumes the ad-hoc `min_orders` floors and flat thresholds into one confidence-based rule,
  then maps confidence + effect-size to warn/critical for human-readable severity.
- Keep the current flat thresholds available as a fallback / override per partner.

### 7.5 Incident correlation **[E]** (fixes L8)
- A correlation layer groups related alerts (system + integration + N merchants sharing a root cause)
  into **one incident** with a blast-radius rollup, instead of N Slack messages.
- Correlation keys: same `pos_partner`, overlapping time, shared error code.

### 7.6 Durable state, history & datastore **[R]** (fixes L7)
- **Live alert state:** a transactional store (Firestore/Cloud SQL) — replaces `state.json`.
- **History (analytics):** append every evaluation, alert transition, and incident to **BigQuery**.
  Enables MTTA/MTTR, alert precision/recall, and threshold back-testing.
- **Snapshots:** land in BigQuery tables with an enforced schema (kills 0-byte/poison-file class of bugs).

### 7.7 Alerting UX & routing **[R/E]** (fixes L9)
- **[R]** Slack **app** (not just webhook) with interactive **Ack / Snooze / Resolve** buttons that write back to state.
- **[R]** Route by **partner/merchant ownership** to the right channel/team.
- **[E]** On-call integration (**PagerDuty/Opsgenie**) for `critical` and system-wide incidents.
- **[E]** Maintenance windows / suppression per partner-merchant for known outages.

### 7.8 Configuration as code **[R]** (fixes L10 partly)
- Thresholds, ownership, routing, and mutes in **versioned YAML** in the repo, validated in CI,
  hot-loaded by the service. No editing JSON on a laptop.

### 7.9 Self-monitoring / dead-man's switch **[R]** (fixes L1)
- The service emits a **heartbeat**; absence of heartbeat pages someone (the current system dies silently).
- **Data-freshness** check is a first-class alert: if the source hasn't advanced in N minutes, alert.

### 7.10 Dimension tables **[R]** (fixes L10)
- Maintained `dim_pos_partner (id → name, owner, on-call routing)` replacing the SQL `CASE`.
- Maintained test/demo flag on merchant/org replacing `LIKE '%test%'`.

### 7.11 Metric hardening **[R]**
- Standardize on **distinct-order** counting across all tiers and the dashboard.
- Re-examine the **timeout = 504** definition with the integrations team; broaden if other
  timeout signatures exist (e.g. specific messages or upstream curl errors).

---

## 8. Non-functional requirements

| Area | Requirement |
|---|---|
| Availability | Monitor service ≥ 99.9%; dead-man's-switch on the monitor itself. |
| Coverage | 24/7 evaluation (severity-based routing, not run-hour gating). |
| Latency | Detection within one cadence interval of source freshness; target ≤ 15 min beyond source lag. |
| Scale | ~2k–3k merchant rows/window today; design for 10×. BQ scan cost negligible now (~100 MB/run) — cost-check at higher cadence. |
| Security | **Service account**, least-privilege read-only; secrets (webhook, tokens) in **Secret Manager**; no creds on disk. |
| Cost | Track BigQuery bytes-scanned; use partitioned/clustered tables; cache baselines. |
| Auditability | Every alert + transition persisted; config changes via reviewed PRs. |

---

## 9. Data model (proposed, BigQuery)

- `fact_pos_order_outcome` (partitioned by date, clustered by pos_partner, merchant_key):
  order-grain outcomes — the canonical fact both live evaluation and history read from.
- `dim_pos_partner`, `dim_merchant` — names, ownership, routing, test flag.
- `baseline_partner_window` — (partner, dow, hour) → robust mean/spread, refreshed nightly.
- `alert_event` — every state transition (id, scope, level, kind, metrics, ts).
- `incident` — correlated incidents with blast-radius + lifecycle timestamps.
- `monitor_heartbeat` — run log for the dead-man's switch.

---

## 10. Rollout plan (phased)

1. **Lift to cloud (parity):** port `monitor` + `collector` to a Cloud Run Job on a service account,
   land snapshots in BigQuery, keep current thresholds/tiers. Removes L1/L3, most of L7.
2. **24/7 + self-monitoring:** continuous cadence, heartbeat, freshness alert, config-as-code. (L2, L9)
3. **Alerting platform:** Slack app with ack/resolve + ownership routing + on-call. (L9)
4. **Detection upgrade:** seasonal robust baselines + binomial significance + incident correlation. (L5, L6, L8, L11)
5. **Latency:** pursue lower-latency source with Data Platform. (L4)

Each phase is independently shippable and keeps the system alerting throughout.

---

## 11. Open questions for the team
1. Is there a **lower-latency** source for POS attempts than the CDC view (Pub/Sub / raw table)?
2. Preferred orchestration — **Cloud Run + Scheduler** vs existing **Airflow/Composer**?
3. On-call tooling in use (**PagerDuty / Opsgenie**) and per-partner ownership mapping owner?
4. Canonical **timeout** definition — confirm 504-only with integrations.
5. Do we need **per-partner threshold overrides** from day one, or is a global default + baseline enough?

---

## Appendix A — current threshold config (`thresholds.json`)
```
system      min 1000  warn fail 1.5% / to 0.8%   crit fail 3%  / to 1.5%
integration min 150   warn fail 4%   / to 2.5%   crit fail 8%  / to 5%
merchant    min 25    warn fail 30%  / to 15%    crit fail 50% / to 30%
baseline    min 30 fails   fire if fail_rate ≥ 2× baseline_mean AND ≥ baseline_mean + 3σ
window_hours 4    renotify_hours 6
```

## Appendix B — reference repo
`~/posdata/.claude/skills/` — `pos-error-monitor/`, `pos-error-collector/`, `pos-error-spike-analyzer/`.
Read these for exact SQL, severity resolution, and Slack Block Kit formatting to replicate.

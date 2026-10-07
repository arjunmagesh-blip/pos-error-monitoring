#!/usr/bin/env python3
"""Evaluate a monitor-window CSV against thresholds.json, dedupe against a
state file, and emit Slack Block Kit JSON for alerts that are NEW, ESCALATED,
still ONGOING (past renotify window), or RESOLVED.

Usage: evaluate.py <window.csv> <thresholds.json> <state.json>
Prints a JSON payload to stdout ONLY if there is something to send; otherwise
prints nothing and exits 0. State file is updated in place.
"""
import csv, json, os, sys, datetime
from collections import defaultdict

csv_path, thr_path, state_path = sys.argv[1], sys.argv[2], sys.argv[3]
now = datetime.datetime.now(datetime.timezone.utc)
now_iso = now.isoformat()

with open(thr_path) as f:
    THR = json.load(f)
try:
    with open(state_path) as f:
        state = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    state = {}

# --- Load window rows ---
rows = []
with open(csv_path) as f:
    for r in csv.DictReader(f):
        for k in ("total", "fails", "timeouts"):
            r[k] = int(r[k] or 0)
        rows.append(r)

def level(rate_cfg_warn, rate_cfg_crit, fail_rate, to_rate):
    """Return 'critical' | 'warn' | None and the driving metric."""
    if fail_rate >= rate_cfg_crit["fail_rate"]:
        return "critical", ("fail", fail_rate)
    if to_rate >= rate_cfg_crit["timeout_rate"]:
        return "critical", ("timeout", to_rate)
    if fail_rate >= rate_cfg_warn["fail_rate"]:
        return "warn", ("fail", fail_rate)
    if to_rate >= rate_cfg_warn["timeout_rate"]:
        return "warn", ("timeout", to_rate)
    return None, None

# --- Build current alert set: id -> dict(level, metric, value, detail) ---
current = {}

# System-wide
sys_total = sum(r["total"] for r in rows)
sys_fail = sum(r["fails"] for r in rows)
sys_to = sum(r["timeouts"] for r in rows)
c = THR["system"]
if sys_total >= c["min_orders"]:
    fr, tr = sys_fail / sys_total, sys_to / sys_total
    lv, drv = level(c["warn"], c["critical"], fr, tr)
    if lv:
        current["system::all"] = {
            "level": lv, "scope": "SYSTEM-WIDE", "name": "all POS traffic",
            "metric": drv[0], "value": drv[1], "orders": sys_total,
            "fails": sys_fail, "timeouts": sys_to}

# Integration
integ = defaultdict(lambda: [0, 0, 0])
for r in rows:
    a = integ[r["pos_partner"]]
    a[0] += r["total"]; a[1] += r["fails"]; a[2] += r["timeouts"]
c = THR["integration"]
for pp, (tot, fl, to) in integ.items():
    if tot >= c["min_orders"]:
        fr, tr = fl / tot, to / tot
        lv, drv = level(c["warn"], c["critical"], fr, tr)
        if lv:
            current[f"integration::{pp}"] = {
                "level": lv, "scope": "INTEGRATION", "name": pp,
                "metric": drv[0], "value": drv[1], "orders": tot,
                "fails": fl, "timeouts": to}

# Baseline deviation (per-integration) — catches a partner surging above its own
# normal fail rate even when the absolute rate is below the integration floor.
# Runs in shadow (dry_run): computed and logged, but not posted, until backtested.
bcfg = THR.get("baseline", {})
if bcfg.get("enabled"):
    skill_dir = os.path.dirname(os.path.abspath(thr_path))
    try:
        with open(os.path.join(skill_dir, "baselines.json")) as f:
            BL = json.load(f).get("partners", {})
    except (FileNotFoundError, json.JSONDecodeError):
        BL = {}
    sigma = bcfg.get("sigma", 3.0)
    min_fails = bcfg.get("min_fails", 30)
    min_ratio = bcfg.get("min_ratio", 2.0)
    bl_events = []
    for pp, (tot, fl, to) in integ.items():
        b = BL.get(pp)
        if not b or tot <= 0 or fl < min_fails:
            continue
        mean, std = b.get("mean", 0.0), b.get("std", 0.0)
        fr = fl / tot
        if mean > 0 and fr >= min_ratio * mean and std > 0 and fr >= mean + sigma * std:
            bl_events.append({
                "level": "warn", "scope": "BASELINE-DEVIATION", "name": pp,
                "metric": "fail", "value": fr, "orders": tot, "fails": fl, "timeouts": to,
                "baseline_mean": mean, "ratio": fr / mean})
    if bcfg.get("dry_run"):
        # Shadow mode: record for backtesting, do NOT alert.
        if bl_events:
            with open(os.path.join(skill_dir, "baseline_shadow.log"), "a") as f:
                for ev in bl_events:
                    f.write(f"{now_iso}\t{ev['name']}\trate={ev['value']*100:.2f}%\t"
                            f"baseline={ev['baseline_mean']*100:.2f}%\tratio={ev['ratio']:.1f}x\t"
                            f"fails={ev['fails']}/{ev['orders']}\n")
            sys.stderr.write("[baseline-shadow] would-fire: " + ", ".join(
                f"{ev['name']}({ev['value']*100:.2f}% vs {ev['baseline_mean']*100:.2f}%, "
                f"{ev['ratio']:.1f}x, {ev['fails']} fails)" for ev in bl_events) + "\n")
    else:
        for ev in bl_events:
            current[f"baseline::{ev['name']}"] = ev

# Merchant
# near_outage: low-volume merchants never reach min_orders in a window, so a
# near-total outage (e.g. 75/78 failing across a day) slips under the floor.
# Fires critical on absolute fails + very high rate, regardless of min_orders.
c = THR["merchant"]
no = c.get("near_outage", {})
for r in rows:
    if r["total"] <= 0:
        continue
    fr, tr = r["fails"] / r["total"], r["timeouts"] / r["total"]
    lv, drv, near = None, None, False
    if r["total"] >= c["min_orders"]:
        lv, drv = level(c["warn"], c["critical"], fr, tr)
    if not lv and no.get("enabled") and r["fails"] >= no["min_fails"] and fr >= no["fail_rate"]:
        lv, drv, near = "critical", ("fail", fr), True
    if lv:
        current[f"merchant::{r['merchant_key']}"] = {
            "level": lv, "scope": "MERCHANT · NEAR-OUTAGE" if near else "MERCHANT",
            "name": f"{r['merchant_name']} ({r['pos_partner']}, {r['country']})",
            "metric": drv[0], "value": drv[1], "orders": r["total"],
            "fails": r["fails"], "timeouts": r["timeouts"],
            "sample": (r.get("sample_message") or "").strip()}

# --- Diff against state -> events ---
renotify = datetime.timedelta(hours=THR.get("renotify_hours", 6))
events = []  # (kind, alert_id, cur_dict)
new_state = {}
LVL_RANK = {"warn": 1, "critical": 2}

for aid, cur in current.items():
    prev = state.get(aid)
    if not prev:
        events.append(("NEW", aid, cur))
        new_state[aid] = {"level": cur["level"], "first_seen": now_iso, "last_notified": now_iso}
    else:
        first_seen = prev.get("first_seen", now_iso)
        last_notified = prev.get("last_notified", now_iso)
        escalated = LVL_RANK[cur["level"]] > LVL_RANK.get(prev.get("level", "warn"), 1)
        try:
            stale = (now - datetime.datetime.fromisoformat(last_notified)) >= renotify
        except ValueError:
            stale = True
        if escalated:
            events.append(("ESCALATED", aid, {**cur, "first_seen": first_seen}))
            new_state[aid] = {"level": cur["level"], "first_seen": first_seen, "last_notified": now_iso}
        elif stale:
            events.append(("ONGOING", aid, {**cur, "first_seen": first_seen}))
            new_state[aid] = {"level": cur["level"], "first_seen": first_seen, "last_notified": now_iso}
        else:
            new_state[aid] = {"level": cur["level"], "first_seen": first_seen, "last_notified": last_notified}

# Resolved: in state but not current
for aid, prev in state.items():
    if aid not in current:
        events.append(("RESOLVED", aid, {
            "scope": aid.split("::")[0].upper(), "name": aid.split("::", 1)[1],
            "level": prev.get("level", "warn")}))

# Persist state (only active alerts)
with open(state_path, "w") as f:
    json.dump(new_state, f, indent=2)

if not events:
    sys.exit(0)

# Audit trail: one line per event to stderr (monitor.sh appends stderr to monitor.log).
for kind, aid, d in events:
    if kind == "RESOLVED":
        sys.stderr.write(f"[alert] RESOLVED {aid}\n")
    else:
        sys.stderr.write(f"[alert] {kind} {d['level']} {d['scope']} {d['name']} "
                         f"{d['metric']}={d['value']*100:.1f}% "
                         f"fails={d['fails']} timeouts={d['timeouts']} orders={d['orders']}\n")

# --- Format Slack Block Kit ---
EMOJI = {"critical": "🔴", "warn": "⚠️"}
KIND_LABEL = {"NEW": "NEW", "ESCALATED": "ESCALATED ⬆️", "ONGOING": "STILL ONGOING", "RESOLVED": "✅ RESOLVED"}
blocks = [{"type": "header", "text": {"type": "plain_text",
          "text": f"POS Error Monitor — {len(events)} update(s)"}}]

# Order: critical first, then warn, resolved last
def sortkey(e):
    kind, aid, d = e
    if kind == "RESOLVED":
        return (3, 0)
    return ({"critical": 0, "warn": 1}.get(d.get("level"), 2), 0)

for kind, aid, d in sorted(events, key=sortkey):
    if kind == "RESOLVED":
        line = f"*{KIND_LABEL[kind]}* — {d['scope']}: {d['name']} has recovered."
    else:
        em = EMOJI.get(d["level"], "")
        pct = f"{d['value']*100:.1f}%"
        metric = "timeout rate" if d["metric"] == "timeout" else "failure rate"
        line = (f"{em} *{KIND_LABEL[kind]} · {d['scope']}* — *{d['name']}*\n"
                f"{metric} *{pct}* over last {THR['window_hours']}h "
                f"({d['fails']} fails / {d['timeouts']} timeouts of {d['orders']} orders)")
        if d.get("baseline_mean") is not None:
            line += (f"\n_{d['ratio']:.1f}× its {d['baseline_mean']*100:.2f}% baseline "
                     f"— low absolute rate, abnormal for this partner_")
        if d.get("sample"):
            line += f"\n_sample:_ `{d['sample'][:140]}`"
    blocks.append({"type": "section", "text": {"type": "mrkdwn", "text": line}})

blocks.append({"type": "context", "elements": [{"type": "mrkdwn",
              "text": f"window ends ~{now.strftime('%Y-%m-%d %H:%M')} UTC · data lags ~1.5h · thresholds in thresholds.json"}]})

print(json.dumps({"blocks": blocks}))

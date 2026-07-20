#!/usr/bin/env python3
"""Compute per-integration (POS partner) failure-rate baselines from the daily
snapshots produced by the pos-error-collector, and write them to baselines.json.

The active monitor's threshold tiers are absolute (fire at >=4% etc.), so a
partner that quietly triples ITS OWN low baseline (e.g. XILNEX 0.1% -> 0.5%)
stays invisible. This file gives the monitor a per-partner "normal" to compare
the current window against.

Baseline for a partner = mean and population-stdev of its DAILY fail_rate over
the trailing N complete days. Rate (not count) is used so a 4h monitor window is
comparable to a full-day baseline. Only days with traffic are counted.

Usage: build_baselines.py [--dir DIR] [--out FILE] [--days N]
Pure standard library.
"""
import argparse
import csv
import glob
import json
import os
import statistics
from collections import defaultdict


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", default=os.path.expanduser("~/posdata/error_snapshots"))
    ap.add_argument("--out", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "baselines.json"))
    ap.add_argument("--days", type=int, default=14)
    args = ap.parse_args()

    files = sorted(glob.glob(os.path.join(args.dir, "pos_errors_*.csv")))
    if not files:
        raise SystemExit(f"No snapshots at {args.dir}")

    # date -> partner -> {total, failed}
    by_date = defaultdict(lambda: defaultdict(lambda: {"total": 0, "failed": 0}))
    for fp in files:
        with open(fp, newline="") as fh:
            for r in csv.DictReader(fh):
                try:
                    cnt = int(r.get("order_count") or 0)
                except ValueError:
                    cnt = 0
                pp = r.get("pos_partner") or "(unknown)"
                d = r["snapshot_date"]
                by_date[d][pp]["total"] += cnt
                if r.get("result") == "FAILED":
                    by_date[d][pp]["failed"] += cnt

    dates = sorted(by_date)[-args.days:]

    # partner -> list of daily fail_rates over the window (days with traffic only)
    series = defaultdict(list)
    orders = defaultdict(list)
    for d in dates:
        for pp, v in by_date[d].items():
            if v["total"] > 0:
                series[pp].append(v["failed"] / v["total"])
                orders[pp].append(v["total"])

    partners = {}
    for pp, rates in series.items():
        if len(rates) < 2:          # need >=2 points for a meaningful stdev
            continue
        partners[pp] = {
            "mean": statistics.fmean(rates),
            "std": statistics.pstdev(rates),
            "n": len(rates),
            "avg_daily_orders": round(statistics.fmean(orders[pp])),
        }

    out = {
        "days": args.days,
        "window_dates": [dates[0], dates[-1]] if dates else [],
        "partners": partners,
    }
    with open(args.out, "w") as f:
        json.dump(out, f, indent=2)
    print(f"baselines: {len(partners)} partners over {len(dates)} days "
          f"({dates[0]}..{dates[-1]}) -> {args.out}")


if __name__ == "__main__":
    main()

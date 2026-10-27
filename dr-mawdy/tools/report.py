#!/usr/bin/env python3
"""Genera la línea temporal real del cutover a partir de logs/*.csv.

Sustituye el rellenado manual de "Hora Inicio Real / Hora Final Real / Duration (Real)".
Salida: logs/timeline.csv y logs/timeline.md (también por pantalla).
"""
import argparse
import csv
import glob
import os


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--log-dir", default="logs")
    a = ap.parse_args()

    latest = {}
    for p in sorted(glob.glob(os.path.join(a.log_dir, "*.csv"))):
        if os.path.basename(p).startswith("timeline"):
            continue
        with open(p, newline="", encoding="utf-8") as f:
            for r in csv.DictReader(f):
                prev = latest.get(r["task_id"])
                if prev is None or r["ts"] >= prev["ts"]:
                    latest[r["task_id"]] = r

    rows = sorted(latest.values(), key=lambda r: (r["start_utc"] or "9999", r["task_id"]))
    cols = ["task_id", "name", "owner", "status", "start_utc", "end_utc", "duration_s", "who"]

    with open(os.path.join(a.log_dir, "timeline.csv"), "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=cols, extrasaction="ignore")
        w.writeheader()
        w.writerows(rows)

    lines = ["| " + " | ".join(cols) + " |", "|" + "---|" * len(cols)]
    for r in rows:
        lines.append("| " + " | ".join((r.get(c) or "").replace("|", "/") for c in cols) + " |")
    md = "\n".join(lines)
    with open(os.path.join(a.log_dir, "timeline.md"), "w", encoding="utf-8") as f:
        f.write(md + "\n")
    print(md)

    bad = [r["task_id"] for r in rows if r["status"] in {"FAILED", "MANUAL_PENDING"}]
    if bad:
        print(f"\nPendientes o fallidas: {', '.join(bad)}")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Runner del runbook DR.

Uso:
  run_tasks.py --phase dr --group ama-db [--mode plan|dry-run|execute]
  run_tasks.py --confirm DR-3.4 DR-4.4

Modos:
  plan     solo imprime lo que haría (no ejecuta ni registra nada)
  dry-run  ejecuta con DRY_RUN=1: los scripts hacen solo lectura / --check
  execute  ejecuta de verdad (requiere DR_ALLOW_EXECUTE=yes en las variables del repo)

Cada tarea deja una fila en logs/<phase>-<group>.csv (auditoría + tiempos reales).
Las tareas manuales quedan MANUAL_PENDING y se cierran con --confirm desde un step manual.
"""
import argparse
import csv
import datetime as dt
import getpass
import glob
import os
import subprocess
import sys

import yaml

FIELDS = ["ts", "task_id", "name", "owner", "status", "start_utc", "end_utc",
          "duration_s", "who", "detail"]
SATISFIED = {"OK", "SKIPPED"}
REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))


def now():
    return dt.datetime.now(dt.timezone.utc)


def iso(t):
    return t.strftime("%Y-%m-%dT%H:%M:%SZ")


def iso_us(t):
    """Con microsegundos: ordena sin ambigüedad el estado más reciente de cada tarea."""
    return t.strftime("%Y-%m-%dT%H:%M:%S.%fZ")


def load_tasks(path):
    with open(path, encoding="utf-8") as f:
        return yaml.safe_load(f)["tasks"]


def load_state(log_dir):
    """Último estado conocido de cada tarea, leyendo todos los CSV del directorio."""
    state = {}
    for p in sorted(glob.glob(os.path.join(log_dir, "*.csv"))):
        with open(p, newline="", encoding="utf-8") as f:
            for row in csv.DictReader(f):
                prev = state.get(row["task_id"])
                if prev is None or row["ts"] >= prev["ts"]:
                    state[row["task_id"]] = row
    return state


def record(path, task, status, start, end, who="runner", detail=""):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    new = not os.path.exists(path)
    dur = int((end - start).total_seconds()) if start and end else ""
    with open(path, "a", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=FIELDS)
        if new:
            w.writeheader()
        w.writerow({
            "ts": iso_us(now()), "task_id": task["id"], "name": task["name"],
            "owner": task.get("owner", ""), "status": status,
            "start_utc": iso(start) if start else "", "end_utc": iso(end) if end else "",
            "duration_s": dur, "who": who, "detail": detail,
        })


def missing_deps(task, state):
    return [d for d in task.get("depends_on", [])
            if state.get(d, {}).get("status") not in SATISFIED]


def notify(msg):
    script = os.path.join(REPO_ROOT, "scripts", "notify.sh")
    try:
        subprocess.run(["bash", script, msg], timeout=30, check=False)
    except Exception as exc:  # la notificación nunca debe romper el cutover
        print(f"[aviso] no se pudo notificar: {exc}")


def banner(text):
    print("\n" + "=" * 78 + f"\n{text}\n" + "=" * 78, flush=True)


def run_group(args):
    tasks = load_tasks(args.runbook)
    groups = args.group.split(",") if args.group else None
    selected = [t for t in tasks if t["phase"] == args.phase
                and (groups is None or t["group"] in groups)]
    if not selected:
        print(f"ERROR: sin tareas para phase={args.phase} group={args.group}", file=sys.stderr)
        return 2

    if args.mode == "execute" and os.environ.get("DR_ALLOW_EXECUTE") != "yes":
        print("ERROR: modo execute bloqueado. Define DR_ALLOW_EXECUTE=yes "
              "(variable de repositorio) solo el día del cutover.", file=sys.stderr)
        return 2

    state = load_state(args.log_dir)
    label = (args.group or "all").replace(",", "+")
    out = os.path.join(args.log_dir, f"{args.phase}-{label}.csv")
    banner(f"FASE {args.phase} | GRUPO {label} | MODO {args.mode}")

    i = 0
    while i < len(selected):
        t = selected[i]
        tid = t["id"]

        if args.mode == "plan":
            kind = "MANUAL" if t["type"] == "manual" else "AUTO"
            extra = f"  run: {t.get('run', '')}" if t["type"] == "auto" else ""
            skip = "  (SKIP)" if t.get("skip") else ""
            print(f"  [{kind}] {tid:<10} {t['name']}  <- {t.get('depends_on', [])}{extra}{skip}")
            i += 1
            continue

        if t.get("skip"):
            ts = now()
            record(out, t, "SKIPPED", ts, ts, detail=t.get("skip_reason", ""))
            state[tid] = {"status": "SKIPPED", "ts": iso_us(ts)}
            print(f"[SKIP] {tid} {t['name']}: {t.get('skip_reason', '')}")
            i += 1
            continue

        miss = missing_deps(t, state)
        if miss:
            print(f"ERROR: {tid} tiene dependencias sin cumplir: {miss}", file=sys.stderr)
            return 2

        if t["type"] == "manual":
            # Anuncia TODAS las manuales consecutivas y detiene el grupo.
            block = []
            while i < len(selected) and selected[i]["type"] == "manual" and not selected[i].get("skip"):
                if missing_deps(selected[i], state):
                    print(f"ERROR: {selected[i]['id']} tiene dependencias sin cumplir: "
                          f"{missing_deps(selected[i], state)}", file=sys.stderr)
                    return 2
                block.append(selected[i])
                i += 1
            ts = now()
            for m in block:
                record(out, m, "MANUAL_PENDING", ts, None, detail=m.get("instructions", "").strip())
                banner(f"ACCIÓN MANUAL [{m['id']}] {m['name']}\nResponsable: {m.get('owner', '-')}\n"
                       f"{m.get('instructions', '').strip()}")
            notify("🟡 Acción manual pendiente:\n" + "\n".join(
                f"- [{m['id']}] {m['name']} ({m.get('owner', '-')})" for m in block))
            print("\nGrupo detenido a la espera de confirmación. "
                  "Cuando esté hecho, lanza el step manual de confirmación del pipeline.")
            return 0

        # ---- tarea automática ----
        banner(f"[{tid}] {t['name']}  (owner: {t.get('owner', '-')})")
        start = now()
        env = dict(os.environ, TASK_ID=tid, DRY_RUN="1" if args.mode == "dry-run" else "0")
        cmd = f"set -euo pipefail; cd '{REPO_ROOT}'; {t['run']}"
        try:
            rc = subprocess.run(["bash", "-c", cmd], env=env,
                                timeout=int(t.get("timeout_min", 30)) * 60).returncode
        except subprocess.TimeoutExpired:
            rc = 124
        end = now()
        status = "OK" if rc == 0 else "FAILED"
        record(out, t, status, start, end, detail=f"rc={rc}")
        state[tid] = {"status": status, "ts": iso_us(end)}
        print(f"[{status}] {tid} ({int((end - start).total_seconds())}s, rc={rc})", flush=True)
        if rc != 0:
            notify(f"🔴 Tarea FALLIDA [{tid}] {t['name']} (rc={rc}). El pipeline se detiene.")
            return 1
        i += 1
    return 0


def confirm(args):
    tasks = {t["id"]: t for t in load_tasks(args.runbook)}
    state = load_state(args.log_dir)
    who = (os.environ.get("BITBUCKET_STEP_TRIGGERER_UUID")
           or os.environ.get("BITBUCKET_STEP_TRIGGERER") or getpass.getuser())
    out = os.path.join(args.log_dir, f"confirm-{now().strftime('%Y%m%dT%H%M%S')}.csv")
    for tid in args.confirm:
        t = tasks.get(tid)
        if t is None or t["type"] != "manual":
            print(f"ERROR: {tid} no existe o no es una tarea manual", file=sys.stderr)
            return 2
        prev = state.get(tid)
        start = now()
        detail = "confirmada sin anuncio previo"
        if prev and prev["status"] == "MANUAL_PENDING" and prev.get("start_utc"):
            start = dt.datetime.strptime(prev["start_utc"], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=dt.timezone.utc)
            detail = "confirmada"
        record(out, t, "OK", start, now(), who=who, detail=detail)
        print(f"[OK] {tid} {t['name']} confirmada por {who}")
    return 0


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--runbook", default=os.path.join(REPO_ROOT, "runbook", "runbook.yaml"))
    ap.add_argument("--log-dir", default="logs")
    ap.add_argument("--phase")
    ap.add_argument("--group", help="uno o varios grupos separados por coma")
    ap.add_argument("--mode", choices=["plan", "dry-run", "execute"], default="dry-run")
    ap.add_argument("--confirm", nargs="+", metavar="TASK_ID")
    args = ap.parse_args()
    if args.confirm:
        sys.exit(confirm(args))
    if not args.phase:
        ap.error("--phase es obligatorio (o usa --confirm)")
    sys.exit(run_group(args))


if __name__ == "__main__":
    main()

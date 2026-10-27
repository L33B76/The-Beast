#!/usr/bin/env python3
"""Valida runbook.yaml. Se ejecuta en cada commit (pipeline `default`).

Comprueba:
  - campos obligatorios, tipos válidos, IDs únicos
  - depends_on existe y aparece ANTES en el fichero (=> sin ciclos y orden ejecutable)
  - tareas auto con `run` y con scripts existentes en el repo
  - ninguna tarea depende de una manual de su mismo grupo que la preceda
    (el runner se detiene en las manuales, esa tarea no se ejecutaría nunca en ese step)
  - cada (phase, group) del runbook se ejecuta en algún step de bitbucket-pipelines.yml
"""
import os
import re
import sys

import yaml

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
REQUIRED = ["id", "phase", "group", "name", "owner", "type"]
PHASES = {"pre", "dr", "test", "rollback", "postgo"}


def main(path):
    with open(path, encoding="utf-8") as f:
        tasks = yaml.safe_load(f)["tasks"]
    errors, seen, by_id = [], [], {}

    for idx, t in enumerate(tasks):
        tid = t.get("id", f"#{idx}")
        for k in REQUIRED:
            if k not in t:
                errors.append(f"{tid}: falta el campo '{k}'")
        if t.get("id") in by_id:
            errors.append(f"{tid}: ID duplicado")
        if t.get("phase") not in PHASES:
            errors.append(f"{tid}: phase inválida '{t.get('phase')}'")
        if t.get("type") not in {"auto", "manual"}:
            errors.append(f"{tid}: type debe ser auto|manual")
        if t.get("type") == "auto":
            if not t.get("run"):
                errors.append(f"{tid}: tarea auto sin 'run'")
            else:
                for rel in re.findall(r"scripts/[\w./-]+", t["run"]):
                    if not os.path.exists(os.path.join(ROOT, rel)):
                        errors.append(f"{tid}: no existe {rel}")
        if t.get("type") == "manual" and not t.get("skip") and not t.get("instructions"):
            errors.append(f"{tid}: tarea manual sin 'instructions'")
        if t.get("skip") and not t.get("skip_reason"):
            errors.append(f"{tid}: skip sin skip_reason")
        for d in t.get("depends_on", []):
            if d not in by_id:
                errors.append(f"{tid}: depende de '{d}' que no existe o aparece después")
        if "id" in t:
            by_id[t["id"]] = t
        seen.append(t)

    # dependencia de una manual anterior del mismo grupo
    for t in tasks:
        for d in t.get("depends_on", []):
            dep = by_id.get(d)
            if (dep and dep["type"] == "manual" and not dep.get("skip")
                    and dep["phase"] == t["phase"] and dep["group"] == t["group"]):
                errors.append(f"{t['id']}: depende de la manual {d} en su mismo grupo "
                              f"('{t['group']}'); sepáralas en grupos distintos")

    # cobertura por el pipeline
    pipe = os.path.join(ROOT, "bitbucket-pipelines.yml")
    if os.path.exists(pipe):
        covered = set()
        for line in open(pipe, encoding="utf-8"):
            if "run_tasks.py" not in line or "--phase" not in line:
                continue
            ph = re.search(r"--phase\s+(\S+)", line)
            gr = re.search(r"--group\s+([\w,-]+)", line)
            if ph and gr:
                for g in gr.group(1).split(","):
                    covered.add((ph.group(1), g))
        for ph, g in sorted({(t["phase"], t["group"]) for t in tasks} - covered):
            errors.append(f"el grupo {ph}/{g} no se ejecuta en bitbucket-pipelines.yml")

    if errors:
        print("RUNBOOK INVÁLIDO:")
        for e in errors:
            print("  -", e)
        return 1
    print(f"Runbook OK: {len(tasks)} tareas, "
          f"{sum(t['type'] == 'auto' for t in tasks)} auto / "
          f"{sum(t['type'] == 'manual' for t in tasks)} manuales.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "runbook", "runbook.yaml")))

#!/usr/bin/env bash
# Funciones comunes. Uso: source "$(dirname "$0")/lib/common.sh"  (desde scripts/*.sh)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export REPO_ROOT
DRY_RUN="${DRY_RUN:-0}"

if [[ -z "${PARAMS_LOADED:-}" ]]; then
  set -a
  # shellcheck source=../../config/params.env
  . "$REPO_ROOT/config/params.env"
  set +a
  export PARAMS_LOADED=1
fi

log()  { printf '%s [%s] %s\n' "$(date -u +%FT%TZ)" "${TASK_ID:--}" "$*"; }
warn() { log "WARN: $*" >&2; }
die()  { log "ERROR: $*" >&2; exit 1; }

# Comando que MODIFICA algo: en dry-run solo se muestra.
run() {
  if [[ "$DRY_RUN" == "1" ]]; then log "DRY-RUN (no ejecutado): $*"; else log "RUN: $*"; "$@"; fi
}

require_env() {
  local v
  for v in "$@"; do [[ -n "${!v:-}" ]] || die "Falta la variable $v"; done
}

# Mensaje de que un valor sigue sin rellenar en params.env
no_todo() {
  local v
  for v in "$@"; do [[ "${!v:-}" != *TODO* ]] || die "$v sigue con valor TODO en config/params.env"; done
}

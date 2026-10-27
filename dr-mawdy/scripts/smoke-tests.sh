#!/usr/bin/env bash
# Smoke tests HTTP por suite (ama | satellites | phoenix) desde config/smoke-tests.csv.
# Solo lectura. Falla si algún endpoint no devuelve el status esperado.
set -euo pipefail
# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"

suite="${1:?Uso: smoke-tests.sh <ama|satellites|phoenix>}"
fail=0; total=0
while IFS=, read -r s name url expected; do
  [[ -z "${s// }" || "$s" == \#* || "$s" != "$suite" ]] && continue
  total=$((total + 1))
  code=$(curl -sk -o /dev/null -w '%{http_code}' --max-time 20 "$url" || true)
  if [[ "$code" == "$expected" ]]; then
    log "OK    $name -> $code"
  else
    log "FALLO $name -> $code (esperado $expected) $url" >&2
    fail=$((fail + 1))
  fi
done < "$REPO_ROOT/config/smoke-tests.csv"

[[ $total -gt 0 ]] || die "No hay tests para la suite '$suite'"
[[ $fail -eq 0 ]] || die "$fail de $total tests fallaron en la suite '$suite'"
log "Suite '$suite': $total/$total OK"

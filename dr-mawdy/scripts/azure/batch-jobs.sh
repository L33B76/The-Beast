#!/usr/bin/env bash
# Habilita/deshabilita jobs de Azure Batch en la cuenta DR. Uso: batch-jobs.sh <enable|disable> <ama|phoenix>
# BATCH_RESOURCE=job-schedule|job (config/params.env). Confirmar qué usa cada aplicación.
set -euo pipefail
# shellcheck source=../lib/common.sh
source "$(dirname "$0")/../lib/common.sh"

action="${1:?Uso: batch-jobs.sh <enable|disable> <ama|phoenix>}"
app="${2:?Falta app}"
no_todo BATCH_ACCOUNT_DR BATCH_RG_DR
case "$app" in ama) jobs="$BATCH_JOBS_AMA" ;; phoenix) jobs="$BATCH_JOBS_PHOENIX" ;; *) die "app inválida: $app" ;; esac
[[ "$action" == "enable" || "$action" == "disable" ]] || die "acción inválida: $action"

az batch account login -n "$BATCH_ACCOUNT_DR" -g "$BATCH_RG_DR" --output none

fail=0
for j in $jobs; do
  if [[ "$BATCH_RESOURCE" == "job-schedule" ]]; then
    run az batch job-schedule "$action" --job-schedule-id "$j" || { warn "falló $action de $j"; fail=$((fail + 1)); }
  else
    run az batch job "$action" --job-id "$j" || { warn "falló $action de $j"; fail=$((fail + 1)); }
  fi
done
[[ $fail -eq 0 ]] || die "$fail job(s) fallaron (en el ensayo GrupoMutualCR falló y se relanzó)"
log "Batch ($app): $action OK en $jobs"

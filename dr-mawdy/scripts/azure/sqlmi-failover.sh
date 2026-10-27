#!/usr/bin/env bash
# Failover planificado del Failover Group de SQL MI. Uso: sqlmi-failover.sh <dr|prod>
# set-primary se lanza contra la región que PASA A SER primaria.
# FORCE_DATA_LOSS=1 usa --allow-data-loss (failover forzado): solo en desastre real, NUNCA en ensayo.
set -euo pipefail
# shellcheck source=../lib/common.sh
source "$(dirname "$0")/../lib/common.sh"

target="${1:?Uso: sqlmi-failover.sh <dr|prod>}"
no_todo SQLMI_FOG_NAME SQLMI_DR_RG SQLMI_PROD_RG
case "$target" in
  dr)   rg="$SQLMI_DR_RG";   loc="$SQLMI_DR_LOCATION" ;;
  prod) rg="$SQLMI_PROD_RG"; loc="$SQLMI_PROD_LOCATION" ;;
  *) die "destino inválido: $target" ;;
esac

role() { az sql instance-failover-group show -g "$rg" --location "$loc" -n "$SQLMI_FOG_NAME" --query replicationRole -o tsv; }

current=$(role)
log "Rol actual en $loc: $current"
if [[ "$current" == "Primary" ]]; then log "Ya es primaria en $loc. Nada que hacer (idempotente)."; exit 0; fi

flags=()
if [[ "${FORCE_DATA_LOSS:-0}" == "1" ]]; then warn "FAILOVER FORZADO: puede haber pérdida de datos"; flags+=(--allow-data-loss); fi

run az sql instance-failover-group set-primary -g "$rg" --location "$loc" -n "$SQLMI_FOG_NAME" ${flags[@]+"${flags[@]}"}

[[ "$DRY_RUN" == "1" ]] && exit 0
for _ in $(seq 1 30); do
  [[ "$(role)" == "Primary" ]] && { log "FoG con primaria en $loc"; exit 0; }
  sleep 20
done
die "El FoG no pasó a Primary en $loc tras 10 minutos"

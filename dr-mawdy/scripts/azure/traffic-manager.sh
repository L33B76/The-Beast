#!/usr/bin/env bash
# Mueve el tráfico entre producción y DR. Uso: traffic-manager.sh <dr|prod>
# Primero HABILITA el destino y después DESHABILITA el origen (nunca se queda sin endpoint).
set -euo pipefail
# shellcheck source=../lib/common.sh
source "$(dirname "$0")/../lib/common.sh"

target="${1:?Uso: traffic-manager.sh <dr|prod>}"
no_todo TM_RG
case "$target" in
  dr)   on="$TM_EP_DR";   off="$TM_EP_PROD" ;;
  prod) on="$TM_EP_PROD"; off="$TM_EP_DR" ;;
  *) die "destino inválido: $target" ;;
esac

set_ep() { # <endpoint> <Enabled|Disabled>
  run az network traffic-manager endpoint update -g "$TM_RG" --profile-name "$TM_PROFILE" \
    --type azureEndpoints -n "$1" --endpoint-status "$2" --output none
}

log "Tráfico -> $target  (habilitar $on, deshabilitar $off)"
set_ep "$on" Enabled
set_ep "$off" Disabled

if [[ "$DRY_RUN" != "1" ]]; then
  az network traffic-manager endpoint list -g "$TM_RG" --profile-name "$TM_PROFILE" \
    --type azureEndpoints --query '[].{endpoint:name,status:endpointStatus,monitor:endpointMonitorStatus}' -o table
  st=$(az network traffic-manager endpoint show -g "$TM_RG" --profile-name "$TM_PROFILE" \
    --type azureEndpoints -n "$on" --query endpointStatus -o tsv)
  [[ "$st" == "Enabled" ]] || die "El endpoint $on no quedó Enabled"
fi

#!/usr/bin/env bash
# "Mobility Site Recovery": IaaS (ASR) + Storage Account + comprobación de Key Vault DR.
# Uso: site-recovery.sh <dr|prod>
set -euo pipefail
# shellcheck source=../lib/common.sh
source "$(dirname "$0")/../lib/common.sh"

target="${1:?Uso: site-recovery.sh <dr|prod>}"
no_todo ASR_VAULT_NAME ASR_VAULT_RG KV_DR_NAME
case "$target" in dr) direction="PrimaryToRecovery" ;; prod) direction="RecoveryToPrimary" ;; *) die "destino inválido: $target" ;; esac

log "== IaaS (ASR) $ASR_VM_NAME: $direction"
export ASR_DIRECTION="$direction" DRY_RUN
pwsh -NoProfile -File "$(dirname "$0")/site-recovery.ps1"

log "== Storage accounts"
if [[ -z "${STORAGE_ACCOUNTS_FAILOVER// }" ]]; then
  log "STORAGE_ACCOUNTS_FAILOVER vacío: no se conmuta ninguna cuenta."
else
  warn "Failover de Storage Account: la cuenta pasa a LRS en la región secundaria y se pierden los datos sin replicar."
  for sa in $STORAGE_ACCOUNTS_FAILOVER; do
    run az storage account failover --name "${sa%%:*}" --resource-group "${sa##*:}" --yes
  done
fi

log "== Key Vault DR accesible"
az keyvault secret list --vault-name "$KV_DR_NAME" --query '[0].name' -o tsv >/dev/null \
  || die "No se puede acceder al Key Vault DR $KV_DR_NAME"
log "Key Vault DR OK"

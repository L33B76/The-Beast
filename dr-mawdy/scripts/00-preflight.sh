#!/usr/bin/env bash
# Preflight de DR. Solo lectura. Ataca las causas de los fallos del ensayo:
# conectividad pod->LDAP/Redis/BBDD, secretos que faltan, Traffic Manager, FoG y Data Guard.
# Acumula todos los fallos y falla al final, para ver el panorama completo.
set -uo pipefail
# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"
set +e

errors=0
fail() { log "FALLO: $*" >&2; errors=$((errors + 1)); }

no_todo TM_RG TM_PROFILE SQLMI_FOG_NAME SQLMI_DR_RG SQLMI_DR_LOCATION KV_DR_NAME || exit 1

log "== 1. Sesión Azure"
az account show --query name -o tsv >/dev/null 2>&1 || fail "sin sesión en Azure"

log "== 2. Traffic Manager: existen los dos endpoints"
for ep in "$TM_EP_PROD" "$TM_EP_DR"; do
  az network traffic-manager endpoint show -g "$TM_RG" --profile-name "$TM_PROFILE" \
    --type azureEndpoints -n "$ep" --query endpointStatus -o tsv >/dev/null 2>&1 \
    && log "OK endpoint $ep" || fail "no existe el endpoint $ep"
done

log "== 3. SQL MI Failover Group: estado y rol"
role=$(az sql instance-failover-group show -g "$SQLMI_DR_RG" --location "$SQLMI_DR_LOCATION" \
  -n "$SQLMI_FOG_NAME" --query replicationRole -o tsv 2>/dev/null)
[[ -n "$role" ]] && log "OK FoG $SQLMI_FOG_NAME, rol en región DR: $role" || fail "no se lee el FoG $SQLMI_FOG_NAME"

log "== 4. Key Vault DR: secretos requeridos"
secrets=$(az keyvault secret list --vault-name "$KV_DR_NAME" --query '[].name' -o tsv 2>/dev/null)
[[ -n "$secrets" ]] || fail "no se pueden listar secretos de $KV_DR_NAME"
while read -r s; do
  [[ -z "$s" || "$s" == \#* ]] && continue
  grep -qx "$s" <<<"$secrets" && log "OK secreto $s" || fail "falta el secreto '$s' en $KV_DR_NAME"
done < "$REPO_ROOT/config/required-secrets.txt"

log "== 5. Conectividad TCP desde el runner DR"
while IFS=, read -r name host port; do
  [[ -z "${name// }" || "$name" == \#* ]] && continue
  if timeout 5 bash -c ">/dev/tcp/$host/$port" 2>/dev/null; then log "OK $name ($host:$port)"
  else fail "sin conectividad a $name ($host:$port)"; fi
done < "$REPO_ROOT/config/connectivity.csv"

log "== 6. Data Guard: ¿listo para switchover?"
DRY_RUN=1 TASK_ID="${TASK_ID:-PRE}" "$REPO_ROOT/scripts/ansible.sh" oracle-preflight.yml \
  -e run_on=oracle_primary -e target_db="$DG_DR_DB" || fail "Data Guard no está listo para switchover"

echo
if [[ $errors -gt 0 ]]; then log "PREFLIGHT KO: $errors comprobación(es) fallida(s)" >&2; exit 1; fi
log "PREFLIGHT OK"

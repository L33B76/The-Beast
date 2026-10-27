#!/usr/bin/env bash
# Login en Azure. Orden de preferencia:
#   1) AZURE_USE_MSI=true  -> identidad administrada de la VM del runner (sin secretos, recomendado)
#   2) AZURE_CLIENT_SECRET -> service principal (variable segura de Bitbucket)
# Se usa con:  bash scripts/lib/az-login.sh   (desde un step del pipeline; la sesión queda en ~/.azure)
set -euo pipefail

if [[ "${AZURE_USE_MSI:-}" == "true" ]]; then
  az login --identity --output none
elif [[ -n "${AZURE_CLIENT_SECRET:-}" ]]; then
  az login --service-principal -u "$AZURE_CLIENT_ID" -p "$AZURE_CLIENT_SECRET" -t "$AZURE_TENANT_ID" --output none
else
  echo "ERROR: define AZURE_USE_MSI=true o AZURE_CLIENT_ID/AZURE_TENANT_ID/AZURE_CLIENT_SECRET" >&2
  exit 1
fi
az account set --subscription "${AZURE_SUBSCRIPTION_ID:?Falta AZURE_SUBSCRIPTION_ID}"
echo "Azure OK: $(az account show --query name -o tsv)"

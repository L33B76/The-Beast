#!/usr/bin/env bash
# Plan de IaC DR Common (solo lectura). Detecta deriva entre Terraform y la realidad.
# exit 0 = sin cambios; exit 2 de terraform (cambios) se trata como AVISO, no como fallo.
set -euo pipefail
# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"

cd "$REPO_ROOT/terraform/dr-common"
# El backend (estado remoto) se configura con -backend-config o variables ARM_* del entorno.
terraform init -input=false -no-color
set +e
terraform plan -input=false -no-color -detailed-exitcode -lock=false
rc=$?
set -e
case $rc in
  0) log "IaC DR Common sin cambios pendientes." ;;
  2) warn "HAY DERIVA entre Terraform y el entorno DR. Revisa el plan antes del cutover." ;;
  *) die "terraform plan falló (rc=$rc)" ;;
esac

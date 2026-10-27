#!/usr/bin/env bash
# Comprueba que no hay BBDD suspect / offline / emergency / sin acceso en el listener del FoG.
# Equivale a la query del runbook (sysdatabases está obsoleta; se usa sys.databases).
# Requiere sqlcmd (mssql-tools) y SQL_USER / SQL_PASSWORD como variables seguras.
set -euo pipefail
# shellcheck source=../lib/common.sh
source "$(dirname "$0")/../lib/common.sh"

no_todo SQL_LISTENER_FQDN
require_env SQL_USER SQL_PASSWORD

query="SET NOCOUNT ON; SELECT name + ' [' + state_desc + ']' FROM sys.databases WHERE state_desc <> 'ONLINE' OR HAS_DBACCESS(name) = 0;"
out=$(sqlcmd -S "$SQL_LISTENER_FQDN" -d master -U "$SQL_USER" -P "$SQL_PASSWORD" -b -h -1 -W -Q "$query")

if [[ -n "${out//[[:space:]]/}" ]]; then
  log "BBDD con problemas:" >&2; echo "$out" >&2
  die "Check DB fallido"
fi
log "Check DB OK en $SQL_LISTENER_FQDN: todas las BBDD ONLINE y accesibles"

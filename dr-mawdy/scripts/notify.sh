#!/usr/bin/env bash
# Notifica a Teams (webhook entrante / Workflows). Sin TEAMS_WEBHOOK_URL solo escribe en el log.
# Uso: notify.sh "mensaje"
set -euo pipefail
msg="${1:?Uso: notify.sh \"mensaje\"}"
printf '%s [NOTIFY] %s\n' "$(date -u +%FT%TZ)" "$msg"
if [[ -n "${TEAMS_WEBHOOK_URL:-}" ]]; then
  payload=$(jq -n --arg t "$msg" '{text: $t}')
  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    echo "DRY-RUN: no se envía a Teams"
  else
    curl -fsS -H 'Content-Type: application/json' -d "$payload" "$TEAMS_WEBHOOK_URL" >/dev/null
  fi
fi

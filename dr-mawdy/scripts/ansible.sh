#!/usr/bin/env bash
# Wrapper de ansible-playbook. En dry-run añade --check (los command/shell no se ejecutan).
# Uso: ansible.sh <playbook.yml> [args de ansible-playbook...]
set -euo pipefail
# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"

pb="${1:?Uso: ansible.sh <playbook.yml> [args...]}"; shift
extra=()
[[ "$DRY_RUN" == "1" ]] && extra+=(--check --diff)

cd "$REPO_ROOT/ansible"
log "ansible-playbook playbooks/$pb ${extra[*]:-} $*"
ansible-playbook -i inventory/hosts.yml "playbooks/$pb" ${extra[@]+"${extra[@]}"} "$@"

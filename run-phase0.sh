#!/bin/bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "==> Installing Ansible collections and roles..."
ansible-galaxy collection install -r requirements.yml
ansible-galaxy role install -r requirements.yml

ansible-playbook \
  --vault-id bootstrap@prompt \
  --ask-become-pass \
  --tags phase0 \
  "$@" \
  local.yml

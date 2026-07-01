#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="${SCRIPT_DIR}/fedora-kde-workstation.ks.in"
HOSTS_FILE="${HOSTS_FILE:-${SCRIPT_DIR}/hosts.yml}"
BUILD_DIR="${SCRIPT_DIR}/build"
STAGE_DIR="${BUILD_DIR}/oemdrv"
KS_FILE="${STAGE_DIR}/ks.cfg"

INSTALL_USER="${INSTALL_USER:-gorschu}"
INSTALL_HOSTNAME="${INSTALL_HOSTNAME:-fedora-kde-test}"
BOOTSTRAP_USER_PASSWORD="fedora-bootstrap-user-password"
BOOTSTRAP_LUKS_PASSPHRASE="fedora-bootstrap-luks-passphrase"

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

sed_escape() {
  printf '%s' "$1" | sed -e 's/[\/&|]/\\&/g'
}

kickstart_quote() {
  printf '"%s"' "$(printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g')"
}

[[ -f "$TEMPLATE" ]] || die "template not found: $TEMPLATE"
[[ -f "$HOSTS_FILE" ]] || die "host config not found: $HOSTS_FILE"
command -v yq >/dev/null 2>&1 || die "yq is required to read host config"
[[ "$INSTALL_HOSTNAME" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*$ ]] || \
  die "INSTALL_HOSTNAME may only contain letters, digits, dots, and dashes"

ISO_FILE="${BUILD_DIR}/fedora-kickstart-oemdrv.${INSTALL_HOSTNAME}.iso"

INSTALL_DISK="$(yq -r ".\"${INSTALL_HOSTNAME}\".disk // \"\"" "$HOSTS_FILE")"
SSH_PUBLIC_KEY="$(yq -r ".\"${INSTALL_HOSTNAME}\".ssh_public_key // \"\"" "$HOSTS_FILE")"
[[ -n "$INSTALL_DISK" ]] || die "missing disk entry for host '${INSTALL_HOSTNAME}' in ${HOSTS_FILE}"
[[ "$INSTALL_DISK" == /dev/disk/by-id/* ]] || \
  die "disk for host '${INSTALL_HOSTNAME}' must be an explicit /dev/disk/by-id path"
[[ "$INSTALL_DISK" != *[[:space:]]* ]] || \
  die "disk for host '${INSTALL_HOSTNAME}' must not contain whitespace"

SSHKEY_LINE=""
if [[ -n "$SSH_PUBLIC_KEY" ]]; then
  [[ "$SSH_PUBLIC_KEY" == ssh-* ]] || die "SSH public key for host '${INSTALL_HOSTNAME}' must start with ssh-"
  [[ "$SSH_PUBLIC_KEY" != *$'\n'* ]] || die "SSH public key for host '${INSTALL_HOSTNAME}' must be a single line"
  SSHKEY_LINE="sshkey --username ${INSTALL_USER} $(kickstart_quote "$SSH_PUBLIC_KEY")"
fi

escaped_user="$(sed_escape "$INSTALL_USER")"
escaped_user_password="$(sed_escape "$BOOTSTRAP_USER_PASSWORD")"
escaped_luks_passphrase="$(sed_escape "$BOOTSTRAP_LUKS_PASSPHRASE")"
escaped_hostname="$(sed_escape "$INSTALL_HOSTNAME")"
escaped_install_disk="$(sed_escape "$INSTALL_DISK")"
escaped_sshkey_line="$(sed_escape "$SSHKEY_LINE")"

mkdir -p "$STAGE_DIR"

sed \
  -e "s|@@USER@@|${escaped_user}|g" \
  -e "s|@@USER_PASSWORD@@|${escaped_user_password}|g" \
  -e "s|@@LUKS_PASSPHRASE@@|${escaped_luks_passphrase}|g" \
  -e "s|@@HOSTNAME@@|${escaped_hostname}|g" \
  -e "s|@@INSTALL_DISK@@|${escaped_install_disk}|g" \
  -e "s|@@SSHKEY_LINE@@|${escaped_sshkey_line}|g" \
  "$TEMPLATE" > "$KS_FILE"

genisoimage \
  -quiet \
  -V OEMDRV \
  -J \
  -r \
  -o "$ISO_FILE" \
  "$STAGE_DIR"

chmod 0600 "$KS_FILE" "$ISO_FILE"

printf 'Host %s install disk: %s\n' "$INSTALL_HOSTNAME" "$INSTALL_DISK"
printf 'Host %s bootstrap credentials: fixed dummy values; rotate with Ansible phase0\n' "$INSTALL_HOSTNAME"
printf 'Host %s data partition: create if absent, preserve if present\n' "$INSTALL_HOSTNAME"
if [[ -n "$SSH_PUBLIC_KEY" ]]; then
  printf 'Host %s SSH public key: configured in %s\n' "$INSTALL_HOSTNAME" "$HOSTS_FILE"
else
  printf 'Host %s SSH public key: none\n' "$INSTALL_HOSTNAME"
fi
printf 'Wrote %s\n' "$KS_FILE"
printf 'Wrote %s\n' "$ISO_FILE"
printf 'Warning: rendered Kickstart artifacts contain temporary bootstrap credentials\n'

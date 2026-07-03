#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/build"
STAGE_DIR="${BUILD_DIR}/oemdrv"
KS_FILE="${STAGE_DIR}/ks.cfg"

INSTALL_HOSTNAME="${INSTALL_HOSTNAME:-fedora-kde-test}"
INSTALL_USER="${INSTALL_USER:-gorschu}"
TARGET_DEVICE=""
ASSUME_YES=false
VERIFY_MOUNT=""

usage() {
  cat <<EOF
Usage: $0 --host HOSTNAME --device /dev/DEVICE [--yes]

Renders the HOSTNAME-specific OEMDRV ISO, writes it to a whole block device,
then verifies the raw bytes and mounted ks.cfg.

Options:
  --host HOSTNAME      Host entry to render from hosts.yml. Default:
                       ${INSTALL_HOSTNAME}
  --user USER          Installer user to render. Default: ${INSTALL_USER}
  --device /dev/PATH   Whole block device to overwrite, such as /dev/sda or
                       /dev/disk/by-id/usb-...
  --yes                Do not prompt for typed confirmation.
  -h, --help           Show this help.

Environment defaults:
  INSTALL_HOSTNAME, INSTALL_USER
EOF
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

cleanup() {
  if [[ -n "$VERIFY_MOUNT" ]]; then
    if mountpoint -q "$VERIFY_MOUNT"; then
      sudo umount "$VERIFY_MOUNT" || true
    fi
    rmdir "$VERIFY_MOUNT" 2>/dev/null || true
  fi
}
trap cleanup EXIT

print_command() {
  printf '+'
  printf ' %q' "$@"
  printf '\n'
}

run() {
  print_command "$@"
  "$@"
}

confirm_target() {
  local reply

  if [[ "$ASSUME_YES" == true ]]; then
    return
  fi
  [[ -t 0 ]] || die "refusing to overwrite ${TARGET_DEVICE} without --yes in non-interactive mode"

  printf 'About to overwrite %s with the OEMDRV ISO.\n' "$TARGET_DEVICE" >&2
  printf 'Type the target path exactly to continue: ' >&2
  read -r reply
  [[ "$reply" == "$TARGET_DEVICE" ]] || die "confirmation did not match target path"
}

mounted_targets_for_device() {
  local node

  while IFS= read -r node; do
    findmnt -rn --source "$node" -o TARGET || true
  done < <(lsblk -nrpo NAME "$TARGET_DEVICE")
}

unmount_target() {
  local mountpoint
  local mounted=()

  mapfile -t mounted < <(mounted_targets_for_device)
  if (( ${#mounted[@]} == 0 )); then
    return
  fi

  printf 'Unmounting filesystems from %s:\n' "$TARGET_DEVICE"
  for mountpoint in "${mounted[@]}"; do
    run sudo umount "$mountpoint"
  done
}

validate_target_device() {
  local target_type

  [[ -n "$TARGET_DEVICE" ]] || die "missing --device /dev/PATH"
  [[ "$TARGET_DEVICE" == /dev/* ]] || die "--device must be a /dev/... path"
  [[ ! -e "$TARGET_DEVICE" || -b "$TARGET_DEVICE" ]] || \
    die "${TARGET_DEVICE} exists but is not a block device"
  [[ -b "$TARGET_DEVICE" ]] || die "${TARGET_DEVICE} is not a block device"

  target_type="$(lsblk -dnro TYPE "$TARGET_DEVICE")"
  [[ "$target_type" == "disk" ]] || \
    die "${TARGET_DEVICE} is type '${target_type}', expected a whole disk device"
}

verify_iso_mount() {
  VERIFY_MOUNT="$(mktemp -d /tmp/oemdrv-verify.XXXXXX)"

  run sudo mount -o ro "$TARGET_DEVICE" "$VERIFY_MOUNT"
  run sudo test -f "${VERIFY_MOUNT}/ks.cfg"
  run sudo cmp "$KS_FILE" "${VERIFY_MOUNT}/ks.cfg"
  run sudo umount "$VERIFY_MOUNT"
  rmdir "$VERIFY_MOUNT"
  VERIFY_MOUNT=""
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host)
      INSTALL_HOSTNAME="${2:-}"
      shift 2
      ;;
    --user)
      INSTALL_USER="${2:-}"
      shift 2
      ;;
    --device)
      TARGET_DEVICE="${2:-}"
      shift 2
      ;;
    --yes)
      ASSUME_YES=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      if [[ -z "$TARGET_DEVICE" && "$1" == /dev/* ]]; then
        TARGET_DEVICE="$1"
        shift
      else
        die "unknown argument: $1"
      fi
      ;;
  esac
done

[[ "$INSTALL_HOSTNAME" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*$ ]] || \
  die "--host may only contain letters, digits, dots, and dashes"

validate_target_device

ISO_FILE="${BUILD_DIR}/fedora-kickstart-oemdrv.${INSTALL_HOSTNAME}.iso"

printf 'Target device:\n'
lsblk -o NAME,PATH,SIZE,TYPE,FSTYPE,LABEL,MODEL,SERIAL,TRAN,MOUNTPOINTS "$TARGET_DEVICE"

confirm_target

run env INSTALL_HOSTNAME="$INSTALL_HOSTNAME" INSTALL_USER="$INSTALL_USER" "${SCRIPT_DIR}/render-kickstart.sh"
[[ -f "$ISO_FILE" ]] || die "seed ISO was not created: $ISO_FILE"
[[ -f "$KS_FILE" ]] || die "Kickstart file was not created: $KS_FILE"

unmount_target

run sudo dd \
  "if=${ISO_FILE}" \
  "of=${TARGET_DEVICE}" \
  bs=4M \
  status=progress \
  conv=fsync \
  oflag=direct
run sync
run sudo blockdev --flushbufs "$TARGET_DEVICE"
run sudo cmp -n "$(stat -c%s "$ISO_FILE")" "$ISO_FILE" "$TARGET_DEVICE"
verify_iso_mount

printf 'Wrote and verified %s on %s\n' "$ISO_FILE" "$TARGET_DEVICE"

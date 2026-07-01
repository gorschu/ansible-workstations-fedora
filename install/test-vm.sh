#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/build"
DISK_DIR="${BUILD_DIR}/vms"
KS_FILE="${BUILD_DIR}/oemdrv/ks.cfg"
INSTALL_BOOT_DIR="${BUILD_DIR}/installer-boot"
INSTALL_KERNEL="${INSTALL_BOOT_DIR}/vmlinuz"
INSTALL_INITRD="${INSTALL_BOOT_DIR}/initrd.img"

VM_NAME="${VM_NAME:-fedora-kde-kickstart-test}"
VM_MEMORY="${VM_MEMORY:-8192}"
VM_VCPUS="${VM_VCPUS:-4}"
VM_DISK_SIZE="${VM_DISK_SIZE:-220G}"
VM_DISK="${VM_DISK:-}"
VM_DISK_SERIAL="${VM_DISK_SERIAL:-fedora-ks-root}"
INSTALL_HOSTNAME="${INSTALL_HOSTNAME:-fedora-kde-test}"
INSTALL_USER="${INSTALL_USER:-gorschu}"
LIBVIRT_CONNECT="${LIBVIRT_CONNECT:-qemu:///session}"
VM_NETWORK="${VM_NETWORK:-}"
VM_SSH_PORT="${VM_SSH_PORT:-2222}"
SSH_FORWARD=true
OS_VARIANT="${OS_VARIANT:-fedora-unknown}"
BOOT_MODE="${BOOT_MODE:-kernel}"
KS_FILE_ARG="inst.ks=file:/ks.cfg"
KS_CDROM_ARG="inst.ks=cdrom:LABEL=OEMDRV:/ks.cfg"
ACTIVE_KS_ARG="$KS_FILE_ARG"

FEDORA_ISO="${FEDORA_ISO:-}"
RECREATE=false
REUSE_DISK=false
PRINT_ONLY=false
NO_AUTOCONSOLE=false

usage() {
  cat <<EOF
Usage: $0 --iso /path/to/Fedora-Everything-netinst.iso [options]

Creates a Fedora KDE Kickstart test VM using netinst/standard installer media.

Options:
  --iso PATH             Fedora netinst/standard installer ISO path. Can also
                         use FEDORA_ISO. Live ISOs are not suitable for the
                         default unattended path.
  --name NAME            VM name. Default: ${VM_NAME}
  --memory MIB           VM memory. Default: ${VM_MEMORY}
  --vcpus N              VM vCPU count. Default: ${VM_VCPUS}
  --disk-size SIZE       qcow2 size for new disk. Default: ${VM_DISK_SIZE}
  --disk PATH            qcow2 path. Default: ${VM_DISK:-${DISK_DIR}/${VM_NAME}.qcow2}
  --disk-serial SERIAL   Virtual disk serial. Default: ${VM_DISK_SERIAL}
  --host HOSTNAME        Host entry to render from hosts.yml. Default:
                         ${INSTALL_HOSTNAME}
  --user USER            Installer user to render. Default: ${INSTALL_USER}
  --connect URI          libvirt URI. Default: ${LIBVIRT_CONNECT}
  --network SPEC         virt-install network spec. Default: user mode for
                         qemu:///session with SSH forwarding, default network
                         for qemu:///system.
  --ssh-port PORT        Forward 127.0.0.1:PORT to guest port 22 when using
                         the default qemu:///session network. Default:
                         ${VM_SSH_PORT}
  --no-ssh-forward       Disable the default qemu:///session SSH forward.
  --os-variant NAME      virt-install OS variant. Default: ${OS_VARIANT}
  --boot-mode MODE       kernel, location, or cdrom. Default: ${BOOT_MODE}
                         kernel: extracts the netinst kernel/initrd, attaches
                         the ISO, and passes stage2 + Kickstart args.
                         location: uses virt-install --location/--initrd-inject.
                         cdrom: boots ISO normally; edit GRUB if needed.
  --recreate             Destroy/undefine an existing VM and recreate its disk.
  --reuse-disk           Reuse an existing qcow2 instead of refusing to continue.
  --no-autoconsole       Do not auto-open a graphical console.
  --print-only           Print the virt-install command without running it.
  -h, --help             Show this help.

Environment defaults:
  FEDORA_ISO, VM_NAME, VM_MEMORY, VM_VCPUS, VM_DISK_SIZE, VM_DISK,
  VM_DISK_SERIAL, INSTALL_HOSTNAME, LIBVIRT_CONNECT, VM_NETWORK, VM_SSH_PORT,
  INSTALL_USER, OS_VARIANT, BOOT_MODE
EOF
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

host_tool_env=(
  env
  -u MISE_SHELL
  -u MISE_EXE
  -u MISE_ROOT
  -u MISE_PROJECT_ROOT
  -u MISE_CONFIG_FILE
  -u VIRTUAL_ENV
  -u PYTHONHOME
  -u PYTHONPATH
  PATH=/usr/local/sbin:/usr/local/bin:/usr/bin:/bin
)

run_host_tool() {
  (
    cd /tmp
    "${host_tool_env[@]}" "$@"
  )
}

print_command() {
  printf '+'
  printf ' %q' "$@"
  printf '\n'
}

iso_volume_id() {
  run_host_tool isoinfo -d -i "$FEDORA_ISO" 2>/dev/null | awk -F': ' '/^Volume id:/ {print $2; exit}'
}

extract_installer_boot_files() {
  mkdir -p "$INSTALL_BOOT_DIR"
  bsdtar -xOf "$FEDORA_ISO" images/pxeboot/vmlinuz > "$INSTALL_KERNEL"
  bsdtar -xOf "$FEDORA_ISO" images/pxeboot/initrd.img > "$INSTALL_INITRD"
  chmod 0644 "$INSTALL_KERNEL" "$INSTALL_INITRD"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --iso)
      FEDORA_ISO="${2:-}"
      shift 2
      ;;
    --name)
      VM_NAME="${2:-}"
      shift 2
      ;;
    --memory)
      VM_MEMORY="${2:-}"
      shift 2
      ;;
    --vcpus)
      VM_VCPUS="${2:-}"
      shift 2
      ;;
    --disk-size)
      VM_DISK_SIZE="${2:-}"
      shift 2
      ;;
    --disk)
      VM_DISK="${2:-}"
      shift 2
      ;;
    --disk-serial)
      VM_DISK_SERIAL="${2:-}"
      shift 2
      ;;
    --host)
      INSTALL_HOSTNAME="${2:-}"
      shift 2
      ;;
    --user)
      INSTALL_USER="${2:-}"
      shift 2
      ;;
    --connect)
      LIBVIRT_CONNECT="${2:-}"
      shift 2
      ;;
    --network)
      VM_NETWORK="${2:-}"
      shift 2
      ;;
    --ssh-port)
      VM_SSH_PORT="${2:-}"
      shift 2
      ;;
    --no-ssh-forward)
      SSH_FORWARD=false
      shift
      ;;
    --os-variant|--osinfo)
      OS_VARIANT="${2:-}"
      shift 2
      ;;
    --boot-mode)
      BOOT_MODE="${2:-}"
      shift 2
      ;;
    --recreate)
      RECREATE=true
      shift
      ;;
    --reuse-disk)
      REUSE_DISK=true
      shift
      ;;
    --no-autoconsole)
      NO_AUTOCONSOLE=true
      shift
      ;;
    --print-only)
      PRINT_ONLY=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

[[ -n "$FEDORA_ISO" ]] || die "missing --iso PATH or FEDORA_ISO"
[[ -f "$FEDORA_ISO" ]] || die "Fedora ISO not found: $FEDORA_ISO"
[[ "$INSTALL_HOSTNAME" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*$ ]] || die "--host may only contain letters, digits, dots, and dashes"
[[ "$VM_DISK_SERIAL" =~ ^[A-Za-z0-9._-]+$ ]] || die "--disk-serial may only contain letters, digits, dots, underscores, and dashes"
[[ "$VM_SSH_PORT" =~ ^[0-9]+$ ]] || die "--ssh-port must be numeric"
(( VM_SSH_PORT >= 1 && VM_SSH_PORT <= 65535 )) || die "--ssh-port must be between 1 and 65535"
SEED_ISO="${BUILD_DIR}/fedora-kickstart-oemdrv.${INSTALL_HOSTNAME}.iso"
FEDORA_ISO="$(realpath "$FEDORA_ISO")"
if [[ -z "$VM_DISK" ]]; then
  VM_DISK="${DISK_DIR}/${VM_NAME}.qcow2"
else
  VM_DISK="$(realpath -m "$VM_DISK")"
fi
if [[ -z "$VM_NETWORK" ]]; then
  if [[ "$LIBVIRT_CONNECT" == "qemu:///system" ]]; then
    VM_NETWORK="network=default,model=virtio"
  elif [[ "$SSH_FORWARD" == true ]]; then
    VM_NETWORK="passt,model=virtio,portForward=127.0.0.1:${VM_SSH_PORT}:22"
  else
    VM_NETWORK="passt,model=virtio"
  fi
fi
case "$BOOT_MODE" in
  kernel|location|cdrom) ;;
  *) die "--boot-mode must be 'kernel', 'location', or 'cdrom'" ;;
esac

mkdir -p "$DISK_DIR"

INSTALL_HOSTNAME="$INSTALL_HOSTNAME" INSTALL_USER="$INSTALL_USER" "${SCRIPT_DIR}/render-kickstart.sh"
[[ -f "$SEED_ISO" ]] || die "seed ISO was not created: $SEED_ISO"
[[ -f "$KS_FILE" ]] || die "Kickstart file was not created: $KS_FILE"

ISO_LABEL="$(iso_volume_id)"
if [[ "$BOOT_MODE" != "cdrom" && "$ISO_LABEL" == *Live* ]]; then
  die "Live ISO detected (${ISO_LABEL}); use Fedora Everything netinst or standard installer ISO for unattended Kickstart"
fi
if [[ "$BOOT_MODE" == "kernel" ]]; then
  [[ -n "$ISO_LABEL" ]] || die "could not determine ISO volume id for $FEDORA_ISO"
  extract_installer_boot_files
  KERNEL_ARGS="inst.stage2=hd:LABEL=${ISO_LABEL} ${KS_CDROM_ARG}"
  ACTIVE_KS_ARG="$KS_CDROM_ARG"
fi

if [[ "$PRINT_ONLY" != true ]]; then
  if run_host_tool virsh --connect "$LIBVIRT_CONNECT" dominfo "$VM_NAME" >/dev/null 2>&1; then
    if [[ "$RECREATE" != true ]]; then
      die "VM '${VM_NAME}' already exists; use --recreate to replace it"
    fi

    run_host_tool virsh --connect "$LIBVIRT_CONNECT" destroy "$VM_NAME" >/dev/null 2>&1 || true
    run_host_tool virsh --connect "$LIBVIRT_CONNECT" undefine "$VM_NAME" --nvram >/dev/null 2>&1 || \
      run_host_tool virsh --connect "$LIBVIRT_CONNECT" undefine "$VM_NAME" >/dev/null 2>&1 || true
  fi

  if [[ -e "$VM_DISK" ]]; then
    if [[ "$RECREATE" == true ]]; then
      rm -f "$VM_DISK"
    elif [[ "$REUSE_DISK" != true ]]; then
      die "disk already exists: ${VM_DISK}; use --recreate or --reuse-disk"
    fi
  fi

  if [[ ! -e "$VM_DISK" ]]; then
    run_host_tool qemu-img create -f qcow2 "$VM_DISK" "$VM_DISK_SIZE"
  fi
fi

virt_install_cmd=(
  virt-install
  --connect "$LIBVIRT_CONNECT"
  --name "$VM_NAME"
  --memory "$VM_MEMORY"
  --vcpus "$VM_VCPUS"
  --cpu host-passthrough
  --boot "uefi,bootmenu.enable=on"
  --disk "path=${VM_DISK},format=qcow2,bus=virtio,serial=${VM_DISK_SERIAL}"
  --network "$VM_NETWORK"
  --graphics spice
  --video virtio
  --os-variant "$OS_VARIANT"
  --check path_in_use=off
)

if [[ "$BOOT_MODE" == "kernel" ]]; then
  virt_install_cmd+=(
    --install "kernel=${INSTALL_KERNEL},initrd=${INSTALL_INITRD},kernel_args=${KERNEL_ARGS}"
    --disk "path=${FEDORA_ISO},device=cdrom"
    --disk "path=${SEED_ISO},device=cdrom"
  )
elif [[ "$BOOT_MODE" == "location" ]]; then
  virt_install_cmd+=(
    --location "$FEDORA_ISO"
    --initrd-inject "$KS_FILE"
    --extra-args "$KS_FILE_ARG"
  )
else
  virt_install_cmd+=(
    --cdrom "$FEDORA_ISO"
    --disk "path=${SEED_ISO},device=cdrom"
  )
fi

if [[ "$NO_AUTOCONSOLE" == true ]]; then
  virt_install_cmd+=(--noautoconsole)
else
  virt_install_cmd+=(--autoconsole graphical)
fi

cat <<EOF
VM:           ${VM_NAME}
Disk:         ${VM_DISK}
Disk serial:  ${VM_DISK_SERIAL}
KS host:      ${INSTALL_HOSTNAME}
KS user:      ${INSTALL_USER}
Network:      ${VM_NETWORK}
Seed ISO:     ${SEED_ISO}
Fedora ISO:   ${FEDORA_ISO}
Libvirt URI:  ${LIBVIRT_CONNECT}
Boot mode:    ${BOOT_MODE}
Kickstart:    ${ACTIVE_KS_ARG}
EOF

if [[ "$BOOT_MODE" == "kernel" ]]; then
  cat <<EOF
Kernel args:  ${KERNEL_ARGS}

EOF
elif [[ "$BOOT_MODE" == "cdrom" ]]; then
  cat <<EOF

If the installer does not auto-detect the OEMDRV seed, edit the Fedora boot
entry and append:

  ${KS_CDROM_ARG}

EOF
fi

if [[ "$LIBVIRT_CONNECT" == "qemu:///session" && "$VM_NETWORK" == passt,*portForward* ]]; then
  cat <<EOF
SSH:          ssh -p ${VM_SSH_PORT} ${INSTALL_USER}@127.0.0.1

EOF
fi

print_command "${host_tool_env[@]}" "${virt_install_cmd[@]}"

if [[ "$PRINT_ONLY" == true ]]; then
  exit 0
fi

run_host_tool "${virt_install_cmd[@]}"

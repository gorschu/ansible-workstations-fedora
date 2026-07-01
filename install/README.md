# Fedora KDE Workstation Install

This directory contains the bare-metal Fedora KDE Kickstart installer flow for
these workstations.

The install is destructive for EFI, `/boot`, and root on the configured target
disk. Partition 9 is special: if it already exists, it must be LUKS and is
preserved; if it is missing, the installer creates it as encrypted Btrfs data.

The `OEMDRV` seed does not contain real secrets. Kickstart uses fixed dummy
bootstrap values and Ansible phase0 replaces them immediately after first boot.

## Requirements

On the machine rendering the seed:

- `yq`
- `genisoimage`
- a Fedora Everything netinst or standard installer ISO
- one USB stick for `OEMDRV`

Do not use Fedora Live ISOs for this flow. They boot a live KDE desktop and do
not automatically start Anaconda from `inst.ks`.

## 1. Configure The Target Host

Add or update the host in `install/hosts.yml`:

```yaml
ssh_keys:
  general: &ssh_key_general "ssh-ed25519 ..."

hephaestus:
  disk: /dev/disk/by-id/nvme-SAMSUNG_MZVLW512HMJP-000L7_S359NX0HC16935_1
  ssh_public_key: *ssh_key_general
```

`disk` must be the full persistent `/dev/disk/by-id/...` path for the install
target. Do not use `/dev/nvme0n1`, `/dev/sda`, or other probe-order names.

The SSH public key is rendered with Kickstart's native `sshkey` command for the
created user, so phase0 can run over SSH after the first boot.

To identify the target disk on the machine before reinstalling:

```bash
lsblk -o NAME,PATH,MODEL,SERIAL,SIZE,TRAN,TYPE,MOUNTPOINTS
ls -l /dev/disk/by-id/
```

## 2. Render The OEMDRV Seed

From the repository root:

```bash
INSTALL_HOSTNAME=hephaestus ./install/render-kickstart.sh
```

This writes:

```text
install/build/oemdrv/ks.cfg
install/build/fedora-kickstart-oemdrv.hephaestus.iso
```

Inspect the rendered target before writing the seed:

```bash
rg '/dev/disk/by-id|user --name|sshkey|repo --name=updates' install/build/oemdrv/ks.cfg
```

The generated files contain the target disk path and dummy bootstrap
credentials. They are ignored by Git.

Dummy first-boot values:

```text
user password:  fedora-bootstrap-user-password
LUKS passphrase: fedora-bootstrap-luks-passphrase
```

## 3. Write The OEMDRV Stick

Identify the OEMDRV USB stick first:

```bash
lsblk -o NAME,PATH,MODEL,SERIAL,SIZE,TRAN,TYPE,MOUNTPOINTS
ls -l /dev/disk/by-id/usb-*
```

Use whole-device paths, not partition paths. In other words, write to
`/dev/disk/by-id/usb-...`, not `/dev/disk/by-id/usb-...-part1`.

Unmount anything mounted from the chosen stick, then write the rendered OEMDRV
ISO:

```bash
sudo dd \
  if=install/build/fedora-kickstart-oemdrv.hephaestus.iso \
  of=/dev/disk/by-id/usb-<oemdrv-stick> \
  bs=4M status=progress conv=fsync oflag=direct
sync
```

The OEMDRV stick is not meant to be booted. It only needs to be present next to
the Fedora installer media.

## 4. Boot And Install

Boot the Fedora installer media with the OEMDRV USB already inserted.

Expected behavior: Anaconda finds the `OEMDRV` volume and starts the Kickstart
install without manual boot options.

If it does not, edit the Fedora boot entry and append:

```text
inst.ks=hd:LABEL=OEMDRV:/ks.cfg
```

For CD-ROM style VM tests, use:

```text
inst.ks=cdrom:LABEL=OEMDRV:/ks.cfg
```

The installer writes `/fedora-workstation-storage.yml` into the installed
system. Phase0 and later storage roles use that file to discover the root/data
LUKS devices and Btrfs UUIDs.

## 5. Run Phase0 Immediately

On first boot, unlock LUKS with the dummy passphrase:

```text
fedora-bootstrap-luks-passphrase
```

The root account is locked. The primary user is `gorschu` with the dummy
password:

```text
fedora-bootstrap-user-password
```

Create the encrypted bootstrap vault if it does not exist yet:

```bash
ansible-vault create --vault-id bootstrap@prompt bootstrap.vault.yml
```

For an existing vault:

```bash
ansible-vault edit --vault-id bootstrap@prompt bootstrap.vault.yml
```

It must contain:

```yaml
vault_bootstrap_luks_passphrase: ...
vault_bootstrap_user_password_hash: "$y$j9T$..."
```

Then run phase0 from the control machine:

```bash
./run-phase0.sh -i inventory/ssh.yml --limit hephaestus
```

Phase0 adds the real LUKS passphrase to root and data, verifies it, removes the
dummy installer LUKS passphrase, and sets the real user password hash.

Reboot after phase0. The dummy LUKS passphrase should no longer work.

## 6. Continue The Ansible Phases

After rebooting and unlocking with the real passphrase:

```bash
./run-playbook.sh -i inventory/ssh.yml --limit hephaestus --tags phase1
```

Phase1 prints a reboot reminder after storage bootstrap. Reboot, then continue:

```bash
./run-playbook.sh -i inventory/ssh.yml --limit hephaestus --tags phase2
./run-playbook.sh -i inventory/ssh.yml --limit hephaestus --tags phase3
./run-playbook.sh -i inventory/ssh.yml --limit hephaestus --tags phase4
```

When running locally on the installed machine, omit `-i inventory/ssh.yml`; the
default local inventory is `inventory/local.yml`.

## Disk Layout

```text
part1  EFI System Partition       1G       /boot/efi
part2  boot                       1G       /boot
part3  cryptroot                  150G     LUKS2 + Btrfs root volume
part9  encrypted data             rest     LUKS2 + Btrfs data volume
```

Root Btrfs subvolumes:

```text
root  -> /
home  -> /home
```

Data Btrfs subvolume:

```text
data  -> created by installer when part9 is new; mounted later by Ansible
```

## VM Test

The VM is not special; it uses the same Kickstart. The helper only gives the VM
disk a deterministic serial so `fedora-kde-test` can use this by-id path:

```text
/dev/disk/by-id/virtio-fedora-ks-root
```

Run from the repo root:

```bash
./install/test-vm.sh --iso /path/to/Fedora-Everything-netinst.iso --recreate
```

The default VM uses passt networking and forwards host port `2222` to guest SSH:

```bash
ssh -p 2222 gorschu@127.0.0.1
```

To test partition 9 preservation, install once, put a file on the data volume,
then reinstall without `--recreate` and with disk reuse:

```bash
./install/test-vm.sh --iso /path/to/Fedora-Everything-netinst.iso --reuse-disk
```

Useful VM options:

```bash
./install/test-vm.sh --iso /path/to/Fedora-Everything-netinst.iso --host hephaestus
./install/test-vm.sh --iso /path/to/Fedora-Everything-netinst.iso --ssh-port 2223
./install/test-vm.sh --iso /path/to/Fedora-Everything-netinst.iso --connect qemu:///system
```

The default VM boot mode extracts the installer kernel/initrd and passes the
Kickstart argument directly. `--boot-mode cdrom` is available when you explicitly
want to test Fedora's normal boot menu and OEMDRV discovery path.

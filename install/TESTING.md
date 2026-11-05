# Fedora workstation testing and upgrade runbook

Use this procedure before adopting a Fedora release or changing the installer.
Validate a fresh installation, an in-place upgrade, and a reinstall preserving
partition 9 separately. A successful upgrade does not validate the installer.

Prefer in-place upgrades for working machines. Reinstall when intentionally
rebuilding a machine or changing its storage layout. The Kickstart recreates
EFI, `/boot`, root, `/home`, and swap. It preserves only partition 9, including
its data and Homebrew subvolumes. Backups of `/home` and `/etc` are still needed.

Commands are run from the repository root on the host unless marked **guest**.
Use only the disposable `fedora-kde-test` inventory for VM provisioning.
Examples target Fedora 45; adjust the release and Python/Ansible versions for
future upgrades. Keep per-run results and logs outside this runbook.

## Final release media gate

Use **final Fedora Everything netinst x86_64 media only**. Do not substitute
Beta, RC, Rawhide, KDE Live, or Workstation Live images. Wait for final media
before starting this release's installation tests.

- [Official Everything downloads](https://fedoraproject.org/misc/#everything)
- [F45 final ISO directory](https://dl.fedoraproject.org/pub/fedora/linux/releases/45/Everything/x86_64/iso/)
- [Fedora signing keys](https://fedoraproject.org/security/)

For future releases, replace `45` in the directory URL and recheck the official
download page. Record the exact ISO filename and compose; do not guess a build
suffix from the release number.

Once final media is published, download the ISO and its matching signed
`CHECKSUM` file into `install/build/isos/`. In that directory, verify the
checksum signature with Fedora's published key and then verify the ISO:

```bash
curl --fail --location --output fedora.gpg https://fedoraproject.org/fedora.gpg
# Set CHECKSUM to the exact downloaded checksum filename.
CHECKSUM=Fedora-Everything-REPLACE-WITH-FINAL-COMPOSE-x86_64-CHECKSUM
gpgv --keyring "${PWD}/fedora.gpg" --output verified-checksums.txt "$CHECKSUM" &&
  sha256sum --check --ignore-missing verified-checksums.txt
```

Both commands must succeed, and the ISO being tested must appear with `OK`.
Compare the signer fingerprint with Fedora's published key information. An
unsigned checksum alone does not satisfy this gate. Keep the ISO, checksum,
signature result, and SHA256 together with the test record.

## Host preparation and checks without a VM

Choose an Ansible version that supports both controller and target Python
([support matrix](https://docs.ansible.com/projects/ansible/latest/reference_appendices/release_and_maintenance.html)).
The project pins core 2.22 directly in mise for Fedora 45's Python 3.15.
Install the configured engine and the collections from `requirements.yml`:

```bash
mise install pipx:ansible-core
mise exec -- ansible-galaxy collection install -r requirements.yml
mise exec -- ansible --version
```

With mise activated in your shell, subsequent Ansible commands use this engine.
Otherwise prefix them with `mise exec --`. The playbook wrappers install the
required collections automatically.

The harness needs KVM access, libvirt session support, UEFI firmware,
`virt-install`, `virsh`, `qemu-img`, `passt`, `bsdtar`, `isoinfo`, `genisoimage`,
and Mike Farah's `yq`. A graphical viewer is needed for interactive boot and
LUKS unlocking. Defaults are 8 GiB RAM, 4 vCPUs, a 220 GiB sparse qcow2, and
host TCP port 2222 forwarded to guest SSH.

```bash
command -v virt-install virsh qemu-img passt bsdtar isoinfo genisoimage yq
yq --version
test -r /dev/kvm && test -w /dev/kvm
virsh --connect qemu:///session list --all
df -h install
bash -n install/test-vm.sh
bash -n install/render-kickstart.sh
bash -n install/write-oemdrv.sh
python3 -m unittest discover -s install/tests -v
INSTALL_HOSTNAME=fedora-kde-test ./install/render-kickstart.sh
```

The Python tests use fake hypervisor tools and temporary sentinel disks. They
check the helper's lifecycle behavior, not a boot or actual partition handling.
Rendering writes ignored seed artifacts but does not install a system.

If a tool is missing from PATH, check the configured Homebrew bin directory
before installing it. If `yq` resolves to an unconfigured mise shim, select an
already installed version with `mise exec yq@<installed-version> -- <command>`
or put that installation's directory on PATH for the command. The helper
intentionally uses system libvirt tools with
mise and Python environment overrides removed.

Inspect `install/build/oemdrv/ks.cfg`: the disk must be
`/dev/disk/by-id/virtio-fedora-ks-root`, never a bare-metal disk. Verify the
hostname, SSH key, `--erroronfail` on all three script sections, and creation
of `/etc/plasma-setup-done` in the final `%post`. Plasma Setup has its own
first-run gate: Anaconda's `firstboot --disable` does not disable it. Kickstart
already supplies the account and initial settings, so its post-install script
creates KDE's [documented completion marker](https://github.com/KDE/plasma-setup#completion-flag-file).
Run
`uvx --from pykickstart ksvalidator -v F45 install/build/oemdrv/ks.cfg` using a pykickstart version
that supports the target release. Do not use `--followincludes`: the storage
include is generated inside the installer. Parser validation does not execute
`%pre`, validate its generated storage layout, or prove package availability.

## Fresh installation

Set the path to the verified final ISO and review the planned command:

```bash
FEDORA_ISO=/absolute/path/to/verified-final-Everything-netinst.iso
./install/test-vm.sh --iso "$FEDORA_ISO" --print-only
./install/test-vm.sh --iso "$FEDORA_ISO"
```

`--print-only` still renders the seed and may extract installer boot files, but
does not modify a VM or its disk. Without an explicit replacement flag, the
helper refuses an existing VM or disk. Use `--recreate` only when intentionally
discarding a previous disposable test disk. Do not run harness instances
concurrently: they share rendered seed and extracted boot files.

The default boot mode passes Kickstart directly. Complete installation and
unlock the first boot with `fedora-bootstrap-luks-passphrase`. The initial
user password is `fedora-bootstrap-user-password`.

For a host without an interactive viewer, add `--no-autoconsole`. In this mode,
`virt-install` returns after launch and the VM can stop when Anaconda finishes.
Once installation has completed, check `virsh --connect qemu:///session domstate
fedora-kde-kickstart-test`; if it is shut off, start the installed system with
`virsh --connect qemu:///session start fedora-kde-kickstart-test`.

Connect to this disposable guest using the same host-key policy as
`inventory/vm.yml`. Load the SSH private key matching the public key in
`install/hosts.yml` into your SSH agent, or supply its path with `-i`:

```bash
ssh -F /dev/null -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  -p 2222 gorschu@127.0.0.1
```

**Guest checks:**

```bash
cat /etc/os-release
test -d /sys/firmware/efi
lsblk -o NAME,SIZE,TYPE,FSTYPE,UUID,MOUNTPOINTS
findmnt /
findmnt /home
sudo cat /fedora-workstation-storage.yml
rpm -q fedora-release-identity-kde-desktop
systemctl is-active sshd
```

Pass when the target release boots in UEFI mode, KDE starts, SSH works, SELinux
is enforcing, partitions 1/2/3/4/9 match the documented layout, and the storage
facts describe the actual devices. On a blank disk, `install.data_preserved`
must be `false`. Save the facts and installer logs outside the guest.

## Credential rotation and storage provisioning

Use a dedicated encrypted test vault, not production credentials. Create
`install/build/vm-bootstrap.vault.yml` using:

```bash
ansible-vault create --vault-id bootstrap@prompt install/build/vm-bootstrap.vault.yml
```

Populate `vault_bootstrap_luks_passphrase` and
`vault_bootstrap_user_password_hash` as described in [README.md](README.md).
Choose a test-only passphrase and generate the password hash interactively,
for example with `openssl passwd -6`. Retain this vault across the preservation
test because partition 9 retains its rotated passphrase.

Run from the host after the target-Python compatibility gate passes:

```bash
./run-phase0.sh -i inventory/vm.yml --limit fedora-kde-test \
  -e bootstrap_credentials_vault_file="${PWD}/install/build/vm-bootstrap.vault.yml"
```

Reboot the guest. Verify the new passphrase works. Test rejection of the dummy
passphrase on **each** encrypted partition without changing keys, in the guest:

```bash
for partition in /dev/vda3 /dev/vda4 /dev/vda9; do
  sudo cryptsetup open --test-passphrase "$partition"
done
```

Enter the dummy passphrase at each prompt; every check must fail. Repeat with
the new passphrase; every check must succeed. Confirm the new login password
works as well. Do not record either password in logs.

Provision the storage baseline from the host:

```bash
ansible-playbook -i inventory/vm.yml --limit fedora-kde-test -K --tags phase1 local.yml
# Reboot and unlock the guest, then:
ansible-playbook -i inventory/vm.yml --limit fedora-kde-test -K \
  --tags phase2 --skip-tags btrbk,homebrew,onepassword,notebook local.yml
```

The second command deliberately tests storage mounting without the other
phase2 integrations. In the guest, check `findmnt /home/gorschu/data`,
`findmnt /home/linuxbrew`, `swapon --show`, `cat /proc/cmdline`, and
`systemctl --failed`. Root, swap and data must unlock after reboot; data must
mount from partition 9; zswap must be enabled and zram disabled.

The current [VM profile](../host_vars/fedora-kde-test.yml) is limited to baseline
bring-up and disables several integrations. Do not treat it as full workstation
coverage. Before phases 2 through 4 are tested in full, review every role's
defaults and create a test-specific vars file for the desired integrations.
Use test credentials and exclude real VPNs, backup destinations, and printers.
Track deliberately skipped roles in the test record.

### Repository checks

On F45, run the RPM Fusion role twice and require `changed=0` on the second run:

```bash
ansible-playbook -i inventory/vm.yml --limit fedora-kde-test -K --tags rpmfusion local.yml
```

In the **guest**, verify `sudo dnf repolist --enabled` includes OpenH264,
RPM Fusion release repositories and stable updates, with no testing repositories.
`rpm -V fedora-repos` must report no changes to the packaged Fedora repository
files. Local enablement lives in `/etc/dnf/repos.override.d/`.
On F45, the OpenH264 vendor file is
`/usr/share/dnf5/repos.d/fedora-cisco-openh264.repo`. Inspect any old modified
definitions in `/etc` after an upgrade before removing them. Keep RPM Fusion's
vendor defaults; resolve incorrect channels before rollout.

Confirm Ansible uses DNF5 with the target's system Python bindings. Keep
signature checks enabled; scope any required local-RPM exception to that
installation task.

To test the sync packages in the disposable VM, explicitly override its disabled
integration settings. No account login or real sync configuration is required:

```bash
ansible-playbook -i inventory/vm.yml --limit fedora-kde-test -K --tags sync_tools \
  -e '{"sync_tools_state":"present","sync_tools_mega_state":"present","sync_tools_insync_state":"present"}' \
  local.yml
```

Check package and metadata signatures remain enabled, the repository URLs use
the guest's Fedora release, and every configured package installs. Include this
profile before and after the separate in-place upgrade to test URL regeneration.

MEGA's RPM scripts recreate `/etc/yum.repos.d/megasync.repo` on every package
installation or update. The role disables that duplicate `MEGAsync` repository
through `/etc/dnf/repos.override.d/90-workstations-mega.repo`; the managed `mega`
repository remains enabled. Check the effective repository list after package
updates, not just the contents of `mega.repo`.

Insync's RPM install script only recognizes an existing repository
by searching for `http://yum.insync.io/`. It otherwise overwrites our HTTPS
definition and drops `repo_gpgcheck`. The role adds a comment containing that
search string before installing Insync; the actual base URL remains HTTPS and
uses Ansible's Fedora-version fact. Verify the file survives package installation
and updates, then require a second role run to report `changed=0`. Recheck this
workaround when Insync fixes its repository detection.

## Reinstall and partition preservation

First complete credential rotation and the storage baseline above. In the
**guest**, create a marker only after confirming the data mount exists:

```bash
mountpoint -q /home/gorschu/data &&
  printf '%s\n' 'Fedora reinstall preservation test' > /home/gorschu/data/reinstall-marker.txt
sha256sum /home/gorschu/data/reinstall-marker.txt
sudo blkid /dev/vda3 /dev/vda4 /dev/vda9
sudo cat /fedora-workstation-storage.yml
sync
sudo systemctl poweroff
```

Save the checksum, root/swap/data LUKS UUIDs and data Btrfs UUID **on the host**.
After the guest is off, run:

```bash
virsh --connect qemu:///session domstate fedora-kde-kickstart-test
./install/test-vm.sh --iso "$FEDORA_ISO" --reuse-disk
```

The helper replaces the shut-off VM definition and resets UEFI variables. It
does not remove or recreate the qcow2. Anaconda then recreates the OS partitions
and preserves partition 9. A running guest is refused; shut it down cleanly.
`--reuse-disk` requires an existing disk and cannot be combined with `--recreate`.

On first boot, root and swap have dummy credentials again. Partition 9 still
has its prior test passphrase. Run phase0 using the **same test vault**, reboot,
then repeat phase1, reboot, and the storage-only phase2 command above.

Pass only when:

- The new installer facts contain `install.data_preserved: true`.
- Partition 9 has the same LUKS UUID and its Btrfs filesystem has the same UUID.
- The marker file has the same SHA256 after data is mounted.
- Root and swap LUKS UUIDs changed, confirming an OS reinstall occurred.
- All encrypted devices accept the real test passphrase and reject the dummy.
- Storage mounts and the installed system boot normally after provisioning.

Also repeat a disposable installation with `--boot-mode cdrom` to test normal
UEFI ISO boot and automatic OEMDRV discovery. If manually adding `inst.ks` is
required, record it as a failure of automatic discovery even if installation
then succeeds. The default kernel boot path cannot prove this behavior.

## In-place upgrade

Use a separate VM initialized from the previous supported final release, or
finish the reinstall test before repurposing the existing VM. Do not boot
Kickstart for an in-place upgrade. Match the workstation's relevant packages
and repository configuration; a minimal VM does not validate third-party apps.

For a separate upgrade-source VM, first verify the previous release's final
ISO. Once any other Kickstart installation has finished, launch:

```bash
PREVIOUS_FEDORA_ISO=/absolute/path/to/verified-previous-final-Everything-netinst.iso
./install/test-vm.sh --iso "$PREVIOUS_FEDORA_ISO" \
  --name fedora-kde-upgrade-test --ssh-port 2223 --memory 4096 --vcpus 2
```

Repeat the credential and storage baseline above, adding `-e ansible_port=2223`
to every Ansible command for this VM; SSH uses `-p 2223`. Keep the inventory
limit `fedora-kde-test`, which selects the disposable VM profile. Include the
enabled sync-tools profile and create the preservation markers before upgrading.
Use isolated harness copies if installations must run concurrently.

Before upgrading, shut down the VM and save its disk and domain definition to
a separate backup location with enough free space. For this example's paths:

```bash
mkdir -p install/build/upgrade-backup
virsh --connect qemu:///session domstate fedora-kde-upgrade-test
virsh --connect qemu:///session dumpxml fedora-kde-upgrade-test \
  > install/build/upgrade-backup/domain.xml
cp --reflink=auto --sparse=always install/build/vms/fedora-kde-upgrade-test.qcow2 \
  install/build/upgrade-backup/before-upgrade.qcow2
```

Confirm `domstate` reports `shut off` before copying. Save the UEFI NVRAM file
referenced by the domain XML if an exact VM rollback is required. Start the VM
again with `virsh --connect qemu:///session start fedora-kde-upgrade-test`.

**Guest**, after final release publication and repository readiness checks:

```bash
sudo dnf --refresh upgrade
# Reboot into the updated old release before continuing.
sudo dnf repolist --enabled
df -h / /boot /boot/efi
sudo dnf system-upgrade download --releasever=45
# Review the transaction, especially removals and third-party repositories.
sudo dnf system-upgrade reboot
```

Unlock LUKS for the offline-upgrade boot, then again after its automatic reboot
into the new release. The offline transaction starts under the old kernel, so
an old-release GRUB label at that stage is expected. Verify `/etc/os-release`
and the running kernel after the final reboot.

Do not add `--allowerasing` automatically. Resolve or explicitly review package
removals. MEGA and Insync intentionally use URLs rendered from Ansible's
`distribution_major_version` fact. They retain the old release during the DNF
transaction. If these repositories cause conflicts, retry the download with
`--disable-repo=mega --disable-repo=insync`; these options apply to that command
without persistently disabling the repositories. Review the resulting package
transaction. Consult the
[DNF5 upgrade instructions](https://dnf5.readthedocs.io/en/latest/commands/system-upgrade.8.html)
and the target release's supported upgrade paths for future releases.

Afterward, verify the target release, original storage UUIDs, marker checksum,
boot/unlock, SSH, desktop login, DNF repositories, and `systemctl --failed`.
Reapply the validated provisioning roles and inspect the changes. An upgrade
does not need phase0; do not reset credentials to installer dummy values.

Inspect `sudo dnf history info last`, `sudo dnf check`, and the upgrade journal.
Use `sudo dnf system-upgrade log` to list recorded upgrades, then select the
displayed positive index with `--number=1` (or the applicable index).
Immediately after the upgrade, `sudo journalctl -b -1 -u
dnf5-offline-transaction.service` also captures its log.

A service exit status of 1 during automatic reboot can result from the
[DNF reboot race](https://github.com/rpm-software-management/dnf5/issues/2896).
Require history status `Ok`, the correct release/kernel, healthy storage,
and successful dependency and follow-up update checks before dismissing it.
If the offline log says OpenPGP checks were skipped, verify that signature
checks succeeded in the preceding download/test stage
([upstream explanation](https://github.com/rpm-software-management/dnf5/issues/2206)).
Retain that log and keep signature checks enabled.

On machines with MEGA or Insync enabled, rerun the sync tools role after the
first boot into the new release. For example, from the control machine:

```bash
./run-playbook.sh -i inventory/ssh.yml --limit HOSTNAME --tags sync_tools
```

Replace `HOSTNAME` with the upgraded workstation's inventory name. Ansible will
gather the new Fedora version and rewrite both repository URLs. Then refresh
and upgrade the enabled sync packages on that machine. The default VM profile
disables these integrations, so testing this step requires a profile with them
enabled.

## Desktop and hardware checks

Test KDE and explicitly enable Niri in a dedicated test profile; the default
VM profile does not enable Niri. For F45, test Ctrl+Alt+F3 and return to the
desktop, German keyboard input, console login, and any manual Niri launch
through `kmscon-launch-gui`. Verify KWallet, the active `org.freedesktop.secrets`
provider, and desktop portals including screen sharing in each desktop.
Check third-party sync tools, VPNs, audio/video, suspend/resume, and backups
where included in the test profile. Hardware graphics and suspend tests still
need a real workstation pilot.

Check both `systemctl --failed` and `systemctl --user --failed`. Investigate
each failure and retain the relevant journal output. In particular, verify
input-method services separately from console keyboard input and graphical login.

## Bare-metal rollout and future reinstalls

Before the first workstation, require passing fresh-install, upgrade and
partition-preservation results for the exact repository revision and release.
Select one pilot machine, then validate hardware and daily workflows before
continuing to the remaining machines.

For an upgrade, verify a restorable backup, available boot filesystem space,
third-party repository readiness, and a usable recovery USB. A Btrfs snapshot
alone does not cover every boot file or external filesystem.

For a reinstall, follow [README.md](README.md) with the correct host-specific
disk by-id. Save `/home`, `/etc`, storage facts, LUKS header backups and recovery
material outside the target disk. Record partition 9's UUID and verify its
passphrase before starting. Do not expect ordinary `/home` files to survive.
If the preserved data passphrase differs from the bootstrap vault's real
passphrase, reconcile that before reinstalling: phase0 cannot unlock it with
the dummy installer credential.

## Test record and acceptance

Keep each run's record and logs in `install/build/results/<release>-<date>/`
or an external durable location. Copy evidence out before recreating root.

Record:

- Repository commit and local diff; ISO filename, SHA256 and signature result.
- Host virtualization versions, VM options, guest release and package versions.
- Ansible engine/collections, inventory overrides, and skipped roles.
- Pass/fail/pending for parser validation, fresh installation, phase0, storage
  provisioning, preservation reinstall, OEMDRV discovery, and in-place upgrade.
- Before/after UUIDs and marker checksums; no passphrases or decrypted vaults.
- Installer logs (`/var/log/anaconda/`, `/root/fedora-workstation-*.log`),
  relevant journal output, Ansible failures, and unresolved issues.

Stop rollout on missing final media, failed credential rotation, changed data
UUID/content, boot failures, or unresolved required-role failures.

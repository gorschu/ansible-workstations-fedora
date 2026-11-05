"""Exercise the VM helper with fake libvirt tools and a sentinel disk.

No hypervisor, ISO download, or real VM is used. Only the isolated copy's tool
PATH and seed renderer are replaced; lifecycle logic is run by Bash unchanged.
"""

import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


INSTALL_DIR = Path(__file__).resolve().parents[1]
SENTINEL = b"existing virtual disk, including preserved partition 9\n"
FAKE_TOOL = r'''#!/usr/bin/python3
import json
import os
from pathlib import Path
import sys

name = Path(sys.argv[0]).name
args = sys.argv[1:]
with open(os.environ["VM_TEST_LOG"], "a") as log:
    log.write(json.dumps([name, *args]) + "\n")
if name == "virsh":
    command = args[2]
    if command == "dominfo":
        sys.exit(0 if os.environ["VM_TEST_EXISTS"] == "1" else 1)
    if command == "domstate":
        print(os.environ["VM_TEST_STATE"])
    if command == "undefine" and os.environ.get("VM_TEST_UNDEFINE_FAIL") == "1":
        sys.exit(1)
    if command == "destroy" and os.environ.get("VM_TEST_DESTROY_FAIL") == "1":
        sys.exit(1)
elif name == "isoinfo":
    print("Volume id: Fedora-Everything-test")
elif name == "qemu-img":
    Path(args[-2]).write_bytes(b"new blank disk\n")
'''


class VmLifecycleTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.log = self.root / "commands.jsonl"
        self.disk = self.root / "guest.qcow2"
        self.disk.write_bytes(SENTINEL)
        self.iso = self.root / "installer.iso"
        self.iso.touch()
        self.script = self.root / "test-vm.sh"
        source = (INSTALL_DIR / "test-vm.sh").read_text()
        old_path = "PATH=/usr/local/sbin:/usr/local/bin:/usr/bin:/bin"
        self.assertEqual(source.count(old_path), 1)
        self.script.write_text(source.replace(old_path, f"PATH={self.bin}:/usr/bin:/bin"))
        for name in ("virsh", "qemu-img", "virt-install", "isoinfo"):
            tool = self.bin / name
            tool.write_text(FAKE_TOOL)
            tool.chmod(0o755)
        renderer = self.root / "render-kickstart.sh"
        renderer.write_text('''#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build/oemdrv
touch build/oemdrv/ks.cfg "build/fedora-kickstart-oemdrv.${INSTALL_HOSTNAME}.iso"
''')
        renderer.chmod(0o755)
        self.env = {
            **os.environ,
            "VM_TEST_LOG": str(self.log),
            "VM_TEST_EXISTS": "1",
            "VM_TEST_STATE": "shut off",
        }

    def run_helper(self, *options):
        return subprocess.run(
            ["bash", str(self.script), "--iso", str(self.iso),
             "--disk", str(self.disk), "--name", "lifecycle-test",
             "--host", "fedora-kde-test", "--connect", "qemu:///session",
             "--boot-mode", "cdrom", "--no-autoconsole", *options],
            env=self.env, capture_output=True, text=True, check=False,
        )

    def commands(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()] if self.log.exists() else []

    def assert_not_installed(self):
        self.assertFalse(any(c[0] in ("qemu-img", "virt-install") for c in self.commands()))
        self.assertEqual(self.disk.read_bytes(), SENTINEL)

    def test_reuse_redefines_stopped_vm_without_changing_disk(self):
        result = self.run_helper("--reuse-disk")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.disk.read_bytes(), SENTINEL)
        commands = self.commands()
        self.assertTrue(any(c[0] == "virsh" and "undefine" in c for c in commands))
        self.assertFalse(any(c[0] == "qemu-img" or "destroy" in c for c in commands))
        self.assertEqual(commands[-1][0], "virt-install")
        self.assertNotIn("path_in_use=off", commands[-1])

    def test_reuse_disk_without_existing_domain(self):
        self.env["VM_TEST_EXISTS"] = "0"
        result = self.run_helper("--reuse-disk")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.disk.read_bytes(), SENTINEL)
        self.assertFalse(any("undefine" in c or c[0] == "qemu-img" for c in self.commands()))

    def test_conflicting_flags_fail_before_tools_run(self):
        result = self.run_helper("--reuse-disk", "--recreate")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("mutually exclusive", result.stderr)
        self.assertEqual(self.commands(), [])
        self.assert_not_installed()

    def test_reuse_requires_disk_before_touching_domain(self):
        self.disk.unlink()
        result = self.run_helper("--reuse-disk")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("requires an existing disk", result.stderr)
        self.assertEqual(self.commands(), [])
        self.assertFalse(self.disk.exists())

    def test_existing_domain_requires_explicit_action(self):
        result = self.run_helper()
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(any("undefine" in c or "destroy" in c for c in self.commands()))
        self.assert_not_installed()

    def test_reuse_refuses_running_domain(self):
        self.env["VM_TEST_STATE"] = "running"
        result = self.run_helper("--reuse-disk")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("must be shut off", result.stderr)
        self.assertFalse(any("undefine" in c or "destroy" in c for c in self.commands()))
        self.assert_not_installed()

    def test_undefine_failure_stops_both_replacement_modes(self):
        self.env["VM_TEST_UNDEFINE_FAIL"] = "1"
        for mode in ("--reuse-disk", "--recreate"):
            with self.subTest(mode=mode):
                result = self.run_helper(mode)
                self.assertNotEqual(result.returncode, 0)
                self.assert_not_installed()

    def test_destroy_failure_stops_recreate(self):
        self.env["VM_TEST_STATE"] = "running"
        self.env["VM_TEST_DESTROY_FAIL"] = "1"
        result = self.run_helper("--recreate")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(any("undefine" in c for c in self.commands()))
        self.assert_not_installed()

    def test_recreate_explicitly_replaces_disk(self):
        result = self.run_helper("--recreate")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotEqual(self.disk.read_bytes(), SENTINEL)
        self.assertEqual([c[0] for c in self.commands()][-2:], ["qemu-img", "virt-install"])

    def test_fresh_install_creates_disk(self):
        self.env["VM_TEST_EXISTS"] = "0"
        self.disk.unlink()
        result = self.run_helper()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(self.disk.is_file())

    def test_print_only_does_not_modify_domain_or_disk(self):
        result = self.run_helper("--reuse-disk", "--print-only")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(any(c[0] == "virsh" for c in self.commands()))
        self.assert_not_installed()


if __name__ == "__main__":
    unittest.main()

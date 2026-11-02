import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "run-darwin.sh"


class DarwinLauncherTests(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.dir.cleanup)
        self.root = Path(self.dir.name)
        self.fw = self.root / "firmware"
        self.fw.mkdir()
        self.qemu = self.root / "qemu"
        self.qemu.write_text(
            "#!/usr/bin/env python3\n"
            "import json,sys\n"
            "print('MOCK_QEMU_ARGS:' + json.dumps(sys.argv[1:]))\n")
        self.qemu.chmod(0o755)
        for n in ("bootkc", "dtree", "sptm", "txm", "ramdisk.dmg", "ramdisk.tc"):
            (self.fw / n).write_bytes(b"apple-fixture")
    def run_script(self, **envvars):
        env = dict(os.environ,
                   HOMEVIEW_QEMU=str(self.qemu),
                   HOMEVIEW_FIRMWARE_DIR=str(self.fw),
                   **envvars)
        return subprocess.run(["bash", str(SCRIPT)], env=env,
                              capture_output=True, text=True)
    @staticmethod
    def args(result):
        return json.loads(next(l.split("MOCK_QEMU_ARGS:", 1)[1]
                      for l in result.stdout.splitlines()
                      if l.startswith("MOCK_QEMU_ARGS:")))
    def test_auto_restores_when_update_not_present(self):
        result = self.run_script(HOMEVIEW_BOOT_VARIANT="auto")
        self.assertEqual(result.returncode, 0, result.stderr)
        args = self.args(result)
        self.assertEqual(args[args.index("-ramdisk")+1],
                         str(self.fw / "ramdisk.dmg"))
        self.assertIn("APPLE_DARWIN_BOOT_VARIANT: restore", result.stdout)
    def test_auto_prefers_authentic_su_ramdisk(self):
        (self.fw / "ramdisk-su.dmg").write_bytes(b"su-fixture")
        (self.fw / "ramdisk-su.tc").write_bytes(b"tc-fixture")
        result = self.run_script(HOMEVIEW_BOOT_VARIANT="auto")
        self.assertEqual(result.returncode, 0, result.stderr)
        args = self.args(result)
        self.assertEqual(args[args.index("-ramdisk")+1],
                         str(self.fw / "ramdisk-su.dmg"))
        self.assertEqual(args[args.index("-tc")+1],
                         str(self.fw / "ramdisk-su.tc"))
        self.assertIn("APPLE_DARWIN_BOOT_VARIANT: software-update", result.stdout)
    def test_partial_software_update_never_falls_back(self):
        (self.fw / "ramdisk-su.dmg").write_bytes(b"su-fixture")
        result = self.run_script(HOMEVIEW_BOOT_VARIANT="auto")
        self.assertEqual(result.returncode, 78)
        self.assertIn("INCOMPLETE_SOFTWARE_UPDATE_FIRMWARE", result.stderr)
        self.assertNotIn("MOCK_QEMU_ARGS", result.stdout)
    def test_missing_restore_trustcache_exits_78_on_bash32_compatible_path(self):
        (self.fw / "ramdisk.tc").unlink()
        result = self.run_script(HOMEVIEW_BOOT_VARIANT="restore")
        self.assertEqual(result.returncode, 78, result.stderr)
        self.assertIn("APPLE_DARWIN_INCOMPLETE_RESTORE_FIRMWARE", result.stderr)
        self.assertNotIn("MOCK_QEMU_ARGS", result.stdout)

    def test_no_bash4_case_conversion(self):
        self.assertNotIn(chr(36) + "{MODE^^}", SCRIPT.read_text())

    def test_explicit_restore_overrides_su(self):
        (self.fw / "ramdisk-su.dmg").write_bytes(b"su-fixture")
        (self.fw / "ramdisk-su.tc").write_bytes(b"tc-fixture")
        result = self.run_script(HOMEVIEW_BOOT_VARIANT="restore")
        self.assertEqual(result.returncode, 0)
        args = self.args(result)
        self.assertEqual(args[args.index("-ramdisk")+1],
                         str(self.fw / "ramdisk.dmg"))
    def test_invalid_variant_rejected(self):
        result = self.run_script(HOMEVIEW_BOOT_VARIANT="installed")
        self.assertEqual(result.returncode, 64)
        self.assertIn("INVALID_VARIANT", result.stderr)
    def test_sptm_txm_pair_is_mandatory_if_either_present(self):
        (self.fw / "txm").unlink()
        result = self.run_script()
        self.assertEqual(result.returncode, 78)
        self.assertIn("SPTM/TXM", result.stderr)


if __name__ == "__main__":
    unittest.main()

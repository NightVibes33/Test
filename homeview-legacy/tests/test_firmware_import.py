import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "import_homeview_firmware.py"
spec = importlib.util.spec_from_file_location("import_homeview_firmware", SCRIPT)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


class FirmwareImportTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.src = self.root / "FAT32" / "HomeView"
        self.src.mkdir(parents=True)
        self.dst = self.root / "linux" / "firmware"
        for name in ("bootkc", "dtree", "sptm", "txm",
                     "ramdisk-su.dmg", "ramdisk-su.tc"):
            (self.src / name).write_bytes(("test-not-Apple-" + name).encode())

    def test_create_import_verify_and_idempotent(self):
        manifest = mod.write_manifest(self.src)
        self.assertEqual(manifest["build"], "24V514")
        self.assertTrue(manifest["integrity_only_not_Apple_signature_verification"])
        self.assertEqual(mod.install(self.src, self.dst), "installed")
        self.assertEqual(mod.install(self.src, self.dst), "already_verified")
        self.assertEqual((self.dst / "bootkc").read_bytes(),
                         (self.src / "bootkc").read_bytes())
        self.assertEqual(mod.verify_directory(self.dst, manifest), manifest["files"])

    def test_source_mutation_rejected(self):
        mod.write_manifest(self.src)
        (self.src / "bootkc").write_bytes(b"corrupted")
        with self.assertRaisesRegex(ValueError, "SHA256"):
            mod.install(self.src, self.dst)
        self.assertFalse(self.dst.exists())

    def test_device_or_build_claim_mismatch_rejected(self):
        manifest = mod.write_manifest(self.src)
        manifest["device"] = "iPhone17,3"
        (self.src / "manifest.json").write_text(json.dumps(manifest))
        with self.assertRaisesRegex(ValueError, "mismatched"):
            mod.install(self.src, self.dst)

    def test_missing_sptm_txm_and_partial_restore_fail(self):
        (self.src / "txm").unlink()
        with self.assertRaisesRegex(ValueError, "Missing prepared"):
            mod.write_manifest(self.src)
        (self.src / "txm").write_bytes(b"txm-test")
        (self.src / "ramdisk-su.tc").unlink()
        with self.assertRaisesRegex(ValueError, "No complete"):
            mod.write_manifest(self.src)

    def test_unknown_and_duplicate_manifest_keys_rejected(self):
        with self.assertRaisesRegex(ValueError, "Unexpected"):
            mod.check_file_set(mod.FILES | {"../evil"})
        mod.write_manifest(self.src)
        raw = (self.src / "manifest.json").read_text()
        (self.src / "manifest.json").write_text(
            '{"schema":1,"schema":2,"format":"unused"}')
        with self.assertRaisesRegex(ValueError, "Duplicate"):
            mod.install(self.src, self.dst)
        (self.src / "manifest.json").write_text(raw)

    def test_source_symlink_and_overwrite_rejected(self):
        mod.write_manifest(self.src)
        (self.src / "bootkc").unlink()
        (self.src / "bootkc").symlink_to(self.src / "dtree")
        with self.assertRaisesRegex(ValueError, "regular"):
            mod.install(self.src, self.dst)

    def test_nonmatching_existing_install_replaced_as_one_package(self):
        original = mod.write_manifest(self.src)
        self.assertEqual(mod.install(self.src, self.dst), "installed")
        (self.src / "bootkc").write_bytes(b"test-binary-v2")
        replacement = mod.write_manifest(self.src)
        self.assertEqual(mod.install(self.src, self.dst), "installed")
        self.assertNotEqual(original["files"]["bootkc"], replacement["files"]["bootkc"])
        self.assertFalse((self.dst.parent / "firmware.previous-import").exists())
        self.assertEqual(mod.verify_directory(self.dst, replacement), replacement["files"])

    def test_small_or_missing_files_rejected(self):
        (self.src / "bootkc").write_bytes(b"")
        with self.assertRaisesRegex(ValueError, "length"):
            mod.write_manifest(self.src)


if __name__ == "__main__":
    unittest.main()

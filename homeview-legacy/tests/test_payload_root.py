import importlib.util
import struct
from pathlib import Path
import unittest

BASE = Path(__file__).resolve().parents[1] / "scripts"


def load(name):
    path = BASE / name
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


mtree = load("compare_payload_mtree.py")
trust = load("static_trustcache.py")


class PayloadRootTests(unittest.TestCase):
    def test_mtree_coverage_counts_missing_breadboard_files(self):
        text = "\n".join((
            "/set type=file uid=0 gid=0 mode=0755",
            "./sbin/launchd type=file size=10",
            "./System/Library/CoreServices/BreadBoard.app/BreadBoard type=file size=20",
            "./System/Library/CoreServices/BreadBoard.app/Info.plist type=file size=4",
            "./usr type=dir",
        ))
        paths = mtree.file_paths(text)
        report = mtree.coverage(paths, ["sbin/launchd",
                                        "System/Library/CoreServices/BreadBoard.app/BreadBoard"])
        self.assertEqual(report["mtree_file_count"], 3)
        self.assertEqual(report["present_file_count"], 2)
        self.assertEqual(report["breadboard_mtree_missing"], 1)
        self.assertTrue(report["mtree_is_not_proof_the_payload_is_that_dmg"])

    def test_version1_trustcache_header(self):
        blob = struct.pack("<I", 1) + b"\x11" * 16 + struct.pack("<I", 2)
        blob += b"\x22" * 22 * 2
        self.assertEqual(trust.count_v1_entries(blob), 2)
        self.assertIsNone(trust.count_v1_entries(struct.pack("<I", 2) + b"\0" * 24))

    def test_stub_root_is_not_booted(self):
        import tempfile
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            image = root / "system.dmg"
            image.write_bytes(b"x" * 2048)
            tc = root / "system.tc"
            tc.write_bytes(struct.pack("<I", 1) + b"\x11" * 16 + struct.pack("<I", 1) + b"\x22" * 22)
            manifest = trust.write_boot_manifest(image, tc, root / "out.json", root / "fw", extracted_files=12)
            self.assertFalse(manifest["boot_payload_root"])
            self.assertTrue(manifest["partial_payload_root"])
            self.assertFalse(image.exists())
            self.assertFalse(manifest["nand_block_device_present"])

    def test_large_root_with_trustcache_is_marked_bootable(self):
        import tempfile
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            image = root / "system.dmg"
            image.write_bytes(b"x" * 4096)
            tc = root / "system.tc"
            tc.write_bytes(struct.pack("<I", 1) + b"\x11" * 16 + struct.pack("<I", 1) + b"\x22" * 22)
            fw = root / "fw"
            fw.mkdir()
            manifest = trust.write_boot_manifest(
                image, tc, root / "out.json", fw, extracted_files=trust.MIN_BOOT_FILES)
            self.assertTrue(manifest["boot_payload_root"])
            self.assertTrue((fw / "system-volume-manifest.json").is_file())
            self.assertTrue(image.exists())

    def test_ans_probe_kextlog_includes_dependency_bit(self):
        import sys
        scripts = Path(__file__).resolve().parents[1] / "scripts"
        sys.path.insert(0, str(scripts))
        spec = importlib.util.spec_from_file_location("probe_homeview_boot", scripts / "probe_homeview_boot.py")
        probe = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(probe)
        args = probe.variant_boot_args("software-update-ans-binding-probe")
        self.assertIn("kextlog=0xffff", args)
        self.assertNotIn("kextlog=0xff ", args)
        lines = probe.driver_evidence_lines(
            "some kext line\nCouldn't alloc class \"AFKResource\"\nRTBuddy(ANS2): start\n")
        self.assertEqual(lines[0], 'Couldn\'t alloc class "AFKResource"')
        volume = load("record_volume_image.py")
        import tempfile
        with tempfile.TemporaryDirectory() as temp:
            blob = Path(temp) / "System.dmg"
            blob.write_bytes(b"dmg")
            report = volume.describe(temp, "system-cryptex")
        self.assertTrue(report["dmg_present"])
        self.assertFalse(report["booted"])
        self.assertFalse(report["nand_block_device_present"])

    def test_bounded_command_times_out(self):
        import tempfile
        bounded = load("run_bounded.py")
        with tempfile.TemporaryDirectory() as temp:
            log = Path(temp) / "log.txt"
            code = bounded.run_bounded(["sleep", "5"], log, 0.2)
            self.assertEqual(code, 124)
            self.assertIn(b"TIMED_OUT", log.read_bytes())

    def test_oversized_image_is_not_staged(self):
        import tempfile
        stage = load("stage_fitting_image.py")
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp) / "src"
            root.mkdir()
            (root / "System.dmg").write_bytes(b"x" * 50)
            dest = Path(temp) / "out.dmg"
            report = stage.stage(root, dest, 10)
            self.assertFalse(report["staged"])
            self.assertFalse(dest.exists())
            self.assertFalse(report["booted"])
            (root / "System.dmg").write_bytes(b"y" * 2000)
            report = stage.stage(root, dest, 3000)
            self.assertTrue(report["staged"])
            self.assertEqual(dest.stat().st_size, 2000)
            self.assertFalse(report["nand_block_device_present"])


if __name__ == "__main__":
    unittest.main()

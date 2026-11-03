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


if __name__ == "__main__":
    unittest.main()

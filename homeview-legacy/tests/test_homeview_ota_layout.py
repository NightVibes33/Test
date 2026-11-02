import importlib.util
from pathlib import Path
import unittest

p = Path(__file__).resolve().parents[1]/"scripts"/"scan_homeview_ota_layout.py"
spec = importlib.util.spec_from_file_location("scan_homeview_ota_layout", p)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


class ListingTests(unittest.TestCase):
    def test_full_and_delta_patterns_not_bootable_proof(self):
        lines = [
            "AssetData/boot/kernelcache.release.homeaccessory17\n",
            "AssetData/payload/replace/System/Library/CoreServices/Foo\n",
            "AssetData/payloadv2/update/System/Library/PrivateFrameworks/Bar\n",
            "AssetData/boot/141-21782-189.dmg\n",
        ]
        got = mod.classify(lines, True)
        self.assertEqual(got["asset_path_counts"]["boot"], 2)
        self.assertEqual(got["asset_path_counts"]["payload"], 1)
        self.assertEqual(got["asset_path_counts"]["payloadv2"], 1)
        self.assertFalse(got["full_installed_rootfs_present_proven"])
        self.assertEqual(got["system_userland_path_markers"][
            "System/Library/CoreServices"], 1)
        self.assertTrue(got["listing_nonempty_and_decoded"])

    def test_failed_archive_listing_not_negative_assertion(self):
        got = mod.classify(["AssetData/boot/firmware.im4p\n"], False)
        self.assertFalse(got["listing_nonempty_and_decoded"])
        self.assertEqual(got["diagnostic_conclusion"], "archive_listing_unavailable")

    def test_invalid_lines_and_bounded_samples(self):
        got = mod.classify(
            ["nothing\n", "\x00AssetData/payload/secret\n",
             *["AssetData/payload/replace/file%d\n" % i for i in range(50)]],
            True)
        self.assertEqual(got["asset_paths_seen"], 50)
        self.assertEqual(len(got["sample_asset_paths"]["payload"]), 18)
        self.assertTrue(got["listing_nonempty_and_decoded"])


if __name__ == "__main__":
    unittest.main()

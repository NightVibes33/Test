import importlib.util
import json
from pathlib import Path
import unittest

PATH = Path(__file__).resolve().parents[1] / "scripts" / "catalog_sibling_firmwares.py"
spec = importlib.util.spec_from_file_location("catalog_sibling_firmwares", PATH)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


class SiblingFirmwareTests(unittest.TestCase):
    def test_homepod_on_a_different_chip_is_not_a_j490_switch(self):
        devices = [
            {"identifier": "AudioAccessory6,1", "name": "HomePod"},
            {"identifier": "iPhone17,1", "name": "iPhone"},
        ]
        firmwares = {
            "AudioAccessory6,1": {
                "boardconfig": "B620AP",
                "boards": [{"cpid": 33537}],
                "firmwares": [{
                    "buildid": "23L773",
                    "version": "26.6",
                    "signed": False,
                    "filesize": 4145609808,
                    "releasedate": "2026-07-27T17:37:58Z",
                }],
            }
        }
        report = mod.summarize(devices, firmwares)
        self.assertEqual(report["homeaccessory_identifiers"], [])
        self.assertIsNone(report["switch_candidate"])
        self.assertFalse(report["switch_recommended"])
        self.assertFalse(report["audioaccessory"][0]["same_chip_as_j490"])
        json.dumps(report)


if __name__ == "__main__":
    unittest.main()

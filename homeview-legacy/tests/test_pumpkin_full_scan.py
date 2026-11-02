import importlib.util
import pathlib
import tempfile
import unittest

p=pathlib.Path(__file__).resolve().parents[1]/"scripts"/"scan_full_pumpkin_diff.py"
spec=importlib.util.spec_from_file_location("scan_full_pumpkin_diff",p)
mod=importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

class ScanTests(unittest.TestCase):
    def test_classification(self):
        with tempfile.TemporaryDirectory() as t:
            root=pathlib.Path(t)
            (root/"a.md").write_text('+ _MobileGestalt_get_pumpkinMode\n+ "PumpkinMode"\n')
            (root/"b.md").write_text('+ "BreadBoard"\n')
            data=mod.scan(root)
            self.assertEqual(data["matches"],3)
            self.assertEqual(data["files_scanned"],2)
            self.assertEqual(data["records"][0]["kind"],"potential_identity_reference")
            self.assertEqual(data["records"][2]["kind"],"homeaccessory_or_breadboard_context")
            self.assertFalse(data["screenshot_verified"])

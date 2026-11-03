import importlib.util
from pathlib import Path
import tempfile
import unittest

PATH = Path(__file__).resolve().parents[1] / "scripts" / "probe_firmwarekit_linkage.py"
spec = importlib.util.spec_from_file_location("probe_firmwarekit_linkage", PATH)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


class FirmwareKitLinkageTests(unittest.TestCase):
    def test_plist_without_macho_is_not_a_linked_class(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / "Info.plist").write_text("AFKResource")
            report = mod.inspect(root)
        self.assertEqual(report["macho_count"], 0)
        self.assertTrue(report["plist_only_if_no_macho"])
        self.assertFalse(report["linked_AFKResource_implementation"])

    def test_large_macho_containing_the_name_counts_as_linked(self):
        with tempfile.TemporaryDirectory() as temp:
            binary = Path(temp) / "AppleFirmwareKit"
            binary.write_bytes(b"\xcf\xfa\xed\xfe" + b"\x00" * 5000 + b"AFKResource\x00")
            report = mod.inspect(temp)
        self.assertTrue(report["linked_AFKResource_implementation"])
        self.assertFalse(report["guest_metaclass_registered_proven"])


if __name__ == "__main__":
    unittest.main()

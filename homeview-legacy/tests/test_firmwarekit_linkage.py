import importlib.util
import struct
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
            # 64-bit little-endian Mach-O, filetype MH_KEXT_BUNDLE (0xB).
            header = struct.pack("<IIIIIII", 0xFEEDFACF, 0x0100000C, 0, 0xB, 0, 0, 0)
            binary.write_bytes(header + b"\x00" * 5000 + b"AFKResource\x00IOService\x00")
            (Path(temp) / "Info.plist").write_text("AFKResource")
            report = mod.inspect(temp)
        self.assertTrue(report["linked_AFKResource_implementation"])
        self.assertTrue(report["sibling_plist_contains_AFKResource"])
        self.assertTrue(report["machos"][0]["is_kext_bundle"])
        self.assertFalse(report["guest_metaclass_registered_proven"])

    def test_executable_without_the_class_string_is_not_the_implementation(self):
        with tempfile.TemporaryDirectory() as temp:
            binary = Path(temp) / "com.apple.driver.AppleFirmwareKit"
            header = struct.pack("<IIIIIII", 0xFEEDFACF, 0x0100000C, 0, 0xB, 1, 0, 0)
            binary.write_bytes(header + b"\x00" * 5000 + b"IOService\x00")
            report = mod.inspect(temp)
        self.assertFalse(report["linked_AFKResource_implementation"])
        self.assertEqual(report["machos"][0]["mach_filetype"], 0xB)
        self.assertEqual(report["machos"][0]["AFK_string_count"], 0)


if __name__ == "__main__":
    unittest.main()

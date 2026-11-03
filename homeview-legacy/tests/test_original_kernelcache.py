import importlib.util
import pathlib
import tempfile
import unittest

path = pathlib.Path(__file__).resolve().parents[1] / "scripts" / "scan_original_kernelcache.py"
spec = importlib.util.spec_from_file_location("scan_original_kernelcache", path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class KernelcacheTests(unittest.TestCase):
    def test_scans_original_byte_tokens_and_reports_only_observation(self):
        data = module.scan_bytes(b"AppleANS\0AppleANS2\0AppleDCP\0RTBuddy")
        self.assertEqual(data["AppleANS"]["match_count"], 2)
        self.assertEqual(data["AppleANS2"]["match_count"], 1)
        self.assertEqual(data["AppleDCP"]["match_count"], 1)
        self.assertEqual(data["RTBuddy"]["sample_file_offsets"], ["0x1c"])
        self.assertFalse(data["AppleANS"]["kext_driver_present_or_loaded_proven"])
        self.assertFalse(data["AppleNVMe"]["literal_bytes_found"])
        self.assertFalse(data["AFKResource"]["literal_bytes_found"])
        present = module.scan_bytes(b"AFKResource\0AppleFirmwareKit")
        self.assertEqual(present["AFKResource"]["match_count"], 1)
        self.assertTrue(present["AppleFirmwareKit"]["literal_bytes_found"])
        self.assertFalse(present["AFKResource"]["kext_driver_present_or_loaded_proven"])

    def test_scans_readonly_file_no_kernel_binary_copied(self):
        with tempfile.TemporaryDirectory() as d:
            p = pathlib.Path(d) / "test-kernel"
            p.write_bytes(b"\xcf\xfa\xed\xfe" + b"\0" * 5000 + b"AppleANS3")
            result = module.scan_file(p)
            self.assertEqual(result["literal_class_symbol_markers"]["AppleANS3"]
                             ["match_count"], 1)
            self.assertTrue(result["MachO_magic_detected"])
            self.assertEqual(len(result["sha256"]), 64)
            self.assertFalse(result["runtime_kext_loading_proven"])

    def test_reject_missing_or_short_original_input(self):
        with tempfile.TemporaryDirectory() as d:
            with self.assertRaisesRegex(ValueError, "missing"):
                module.scan_file(pathlib.Path(d) / "none")


if __name__ == "__main__":
    unittest.main()

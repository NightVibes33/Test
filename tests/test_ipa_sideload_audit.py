"""Offline regression tests for IPA structural and encryption inspection."""
import plistlib
import struct
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from ipa_sideload_audit import audit, macho_slices  # noqa: E402


def thin_macho(cryptid=None):
    if cryptid is None:
        return struct.pack("<IiiIIIII", 0xFEEDFACF, 0x100000C, 0, 2, 0, 0, 0, 0)
    return (struct.pack("<IiiIIIII", 0xFEEDFACF, 0x100000C, 0, 2,
                        1, 24, 0, 0)
            + struct.pack("<IIIIII", 0x2C, 24, 0x1000, 0x1000, cryptid, 0))


def sample_ipa(path, include_plist=True, include_executable=True, cryptid=None):
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
        if include_plist:
            z.writestr("Payload/Example.app/Info.plist", plistlib.dumps({
                "CFBundleIdentifier": "com.example.sample",
                "CFBundleExecutable": "Example",
                "CFBundlePackageType": "APPL",
            }))
        if include_executable:
            z.writestr("Payload/Example.app/Example", thin_macho(cryptid))


class IPAAuditTests(unittest.TestCase):
    def test_valid_archive_with_unencrypted_binary(self):
        with tempfile.TemporaryDirectory() as d:
            path = Path(d) / "valid.ipa"
            sample_ipa(path)
            result = audit(path)
            self.assertTrue(result["ready_for_resigning"], result["errors"])
            self.assertEqual(result["executables"][0]["slices"][0]["cryptids"], [])

    def test_missing_main_plist_blocks(self):
        with tempfile.TemporaryDirectory() as d:
            path = Path(d) / "missing-plist.ipa"
            sample_ipa(path, include_plist=False)
            result = audit(path)
            self.assertFalse(result["ready_for_resigning"])
            self.assertTrue(any("Missing main app Info.plist" in x
                                for x in result["errors"]))

    def test_missing_main_executable_blocks(self):
        with tempfile.TemporaryDirectory() as d:
            path = Path(d) / "missing-exe.ipa"
            sample_ipa(path, include_executable=False)
            result = audit(path)
            self.assertFalse(result["ready_for_resigning"])
            self.assertTrue(any("Missing main executable" in x
                                for x in result["errors"]))

    def test_encrypted_binary_blocks(self):
        with tempfile.TemporaryDirectory() as d:
            path = Path(d) / "encrypted.ipa"
            sample_ipa(path, cryptid=1)
            result = audit(path)
            self.assertFalse(result["ready_for_resigning"])
            self.assertTrue(any("Encrypted Mach-O" in x
                                for x in result["errors"]))

    def test_encryption_info_zero_is_unencrypted(self):
        self.assertFalse(macho_slices(thin_macho(0))[0]["encrypted"])

    def test_corrupt_executable_blocks(self):
        with tempfile.TemporaryDirectory() as d:
            path = Path(d) / "corrupt.ipa"
            with zipfile.ZipFile(path, "w") as z:
                z.writestr("Payload/Example.app/Info.plist", plistlib.dumps({
                    "CFBundleIdentifier": "com.example.sample",
                    "CFBundleExecutable": "Example",
                }))
                z.writestr("Payload/Example.app/Example", b"broken")
            result = audit(path)
            self.assertFalse(result["ready_for_resigning"])
            self.assertTrue(any("Invalid executable" in x
                                for x in result["errors"]))


if __name__ == "__main__":
    unittest.main()

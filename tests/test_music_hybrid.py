"""Synthetic regression tests for legacy Music + modern fragment assembly."""
import plistlib
import struct
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from build_music_hybrid import build, sha256


def macho(cryptid=0):
    return (struct.pack("<IiiIIIII", 0xFEEDFACF, 0x100000C, 0, 2, 1, 24, 0, 0)
            + struct.pack("<IIIIII", 0x2C, 24, 0x1000, 0x1000, cryptid, 0))


def plist(name, ident):
    return plistlib.dumps({
        "CFBundleExecutable": name,
        "CFBundleIdentifier": ident,
        "CFBundlePackageType": "APPL",
        "MinimumOSVersion": "15.0",
    })


def fixtures(folder, cryptid=0):
    old = Path(folder) / "old.ipa"
    new = Path(folder) / "modern.ipa"
    with zipfile.ZipFile(old, "w") as z:
        z.writestr("Payload/Music.app/Info.plist", plist("Music", "com.apple.Music"))
        z.writestr("Payload/Music.app/Music", macho(cryptid))
        z.writestr("Payload/Music.app/Assets.car", b"old interface assets")
        z.writestr("Payload/Music.app/PlugIns/Old.appex/Info.plist",
                   plist("Old", "com.apple.Music.Old"))
        z.writestr("Payload/Music.app/PlugIns/Old.appex/Old", macho())
    with zipfile.ZipFile(new, "w") as z:
        ext = "Payload/Music.app/PlugIns/MusicMessagesApp.appex/"
        z.writestr(ext + "Info.plist", plist("MusicMessagesApp", "com.apple.Music.Messages"))
        z.writestr(ext + "MusicMessagesApp", macho())
        z.writestr(ext + "Resource.txt", b"new extension")
    return old, new


class HybridTests(unittest.TestCase):
    def test_assembles_real_old_executable_and_new_extension(self):
        with tempfile.TemporaryDirectory() as d:
            old, new = fixtures(d)
            out = Path(d) / "hybrid.ipa"
            report = build(old, new, out, "com.nightvibes33.applemusic27",
                           expected_hash=sha256(new))
            self.assertTrue(out.is_file())
            self.assertEqual(len(report["modern_extensions"]), 1)
            with zipfile.ZipFile(out) as z:
                root = "Payload/Music.app/"
                info = plistlib.loads(z.read(root + "Info.plist"))
                ext_info = plistlib.loads(z.read(
                    root + "PlugIns/MusicMessagesApp.appex/Info.plist"))
                self.assertEqual(info["CFBundleIdentifier"], "com.nightvibes33.applemusic27")
                self.assertEqual(ext_info["CFBundleIdentifier"],
                                 "com.nightvibes33.applemusic27.Messages")
                self.assertEqual(z.read(root + "Music"), macho())
                self.assertNotIn(root + "PlugIns/Old.appex/Old", z.namelist())
                self.assertIn(root + "PlugIns/MusicMessagesApp.appex/Resource.txt", z.namelist())

    def test_main_only_has_no_extensions(self):
        with tempfile.TemporaryDirectory() as d:
            old, new = fixtures(d)
            out = Path(d) / "main-only.ipa"
            report = build(old, new, out, "com.nightvibes33.applemusic27", main_only=True)
            self.assertEqual(report["modern_extensions"], [])
            with zipfile.ZipFile(out) as z:
                self.assertFalse(any("/PlugIns/" in n for n in z.namelist()))

    def test_reject_encrypted_old_executable(self):
        with tempfile.TemporaryDirectory() as d:
            old, new = fixtures(d, cryptid=1)
            out = Path(d) / "blocked.ipa"
            with self.assertRaisesRegex(ValueError, "FairPlay encrypted"):
                build(old, new, out, "com.nightvibes33.applemusic27")
            self.assertFalse(out.exists())

    def test_reject_mismatched_fragment_hash(self):
        with tempfile.TemporaryDirectory() as d:
            old, new = fixtures(d)
            with self.assertRaisesRegex(ValueError, "SHA-256 mismatch"):
                build(old, new, Path(d) / "bad.ipa", "com.nightvibes33.applemusic27",
                      expected_hash="0" * 64)


if __name__ == "__main__":
    unittest.main()

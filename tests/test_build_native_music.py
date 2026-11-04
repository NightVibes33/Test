"""Regression checks: native Music source only, never legacy fallback."""
import plistlib
import struct
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace

sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
from build_native_music import build,mach_info

def mach(crypt=0):
    header=struct.pack('<IiiIIIII',0xfeedfacf,0x100000c,0,2,1,24,0,0)
    load=struct.pack('<IIIIII',0x2c,24,0,0,crypt,0)
    return header+load

def fixture(base,encrypted=False,remove_main=False,os='com.apple.Music'):
    app=Path(base)/'Applications/Music.app'
    app.mkdir(parents=True)
    (app/'Info.plist').write_bytes(plistlib.dumps({
        'CFBundleIdentifier':os,'CFBundleExecutable':'Music'}))
    if not remove_main:(app/'Music').write_bytes(mach(1 if encrypted else 0))
    for i in range(12):(app/f'asset{i}.dat').write_bytes(bytes([i]))
    return app

def args(base,out):
    return SimpleNamespace(extracted=Path(base),output=Path(out),
        bundle_id='com.nightvibes33.music.native27',main_only=False,
        expected_build='24A446')

class Tests(unittest.TestCase):
    def test_native_complete(self):
        with tempfile.TemporaryDirectory() as d:
            fixture(d)
            out=Path(d)/'modern.ipa'
            build(args(d,out))
            self.assertTrue(out.is_file())
            import zipfile
            with zipfile.ZipFile(out) as z:
                p=plistlib.loads(z.read('Payload/Music.app/Info.plist'))
                self.assertEqual(p['CFBundleIdentifier'],'com.nightvibes33.music.native27')
                self.assertEqual(z.testzip(),None)
    def test_missing_main_binary_must_fail(self):
        with tempfile.TemporaryDirectory() as d:
            fixture(d,remove_main=True)
            with self.assertRaisesRegex(ValueError,'Missing native'):
                build(args(d,Path(d)/'out.ipa'))
    def test_encryption_must_fail(self):
        with tempfile.TemporaryDirectory() as d:
            fixture(d,encrypted=True)
            with self.assertRaisesRegex(ValueError,'encrypted'):
                build(args(d,Path(d)/'out.ipa'))
    def test_unrelated_bundle_must_fail(self):
        with tempfile.TemporaryDirectory() as d:
            fixture(d,os='com.example.Music')
            with self.assertRaisesRegex(ValueError,'original Apple Music'):
                build(args(d,Path(d)/'out.ipa'))
    def test_macho_parser(self):
        self.assertFalse(mach_info(mach(0))[0]['encrypted'])
        self.assertTrue(mach_info(mach(1))[0]['encrypted'])

if __name__=='__main__':unittest.main()

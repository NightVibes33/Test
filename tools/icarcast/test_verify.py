"""Reject fake decryption before releasing any IPA."""
import struct
import tempfile
import unittest
from pathlib import Path
from zipfile import ZipFile
from verify_ipa import macho_encryption, verify

class VerifyTests(unittest.TestCase):
    def test_reject_cryptid_only_patch(self):
        data = bytearray(0x2000)
        struct.pack_into('<IIIIIIII', data, 0, 0xfeedfacf, 0x0100000c, 0, 2, 1, 24, 0, 0)
        struct.pack_into('<IIIIII', data, 32, 0x2c, 24, 0x1000, 0x1000, 1, 0)
        data[0x1000:] = bytes(range(256)) * 16
        self.assertEqual(macho_encryption(data)[0]['cryptid'], 1)
        patched = bytearray(data)
        struct.pack_into('<I', patched, 32 + 16, 0)
        with tempfile.TemporaryDirectory() as d:
            src, out = Path(d) / 'encrypted.ipa', Path(d) / 'fake.ipa'
            for path, binary in [(src, data), (out, patched)]:
                with ZipFile(path, 'w') as z:
                    z.writestr('Payload/Fake.app/Fake', binary)
            with self.assertRaisesRegex(ValueError, 'cryptid-only patch'):
                verify(src, out)

    def test_reject_sc_info(self):
        with tempfile.TemporaryDirectory() as d:
            src, out = Path(d) / 'src.ipa', Path(d) / 'out.ipa'
            for path in (src, out):
                with ZipFile(path, 'w') as z:
                    z.writestr('Payload/Fake.app/SC_Info/Fake.sinf', b'sensitive')
            with self.assertRaisesRegex(ValueError, 'SC_Info'):
                verify(src, out)

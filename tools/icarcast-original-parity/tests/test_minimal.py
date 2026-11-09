import importlib.util
from pathlib import Path
import struct
import unittest
p=Path(__file__).resolve().parents[1]/"scripts"/"repack_minimal.py"
spec=importlib.util.spec_from_file_location("repack_minimal",p)
mod=importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

def sample(encrypted):
    d=bytearray(128)
    struct.pack_into("<I",d,0,0xfeedfacf)
    struct.pack_into("<I",d,16,1)
    struct.pack_into("<I",d,20,24)
    struct.pack_into("<II",d,32,0x2c,24)
    struct.pack_into("<III",d,40,64,32,int(encrypted))
    d[64:96]=b"\x7f"*32 if encrypted else b"\x12"*32
    return bytes(d)

class TestMinimal(unittest.TestCase):
    def test_decryption_only_changes_fairplay_region(self):
        self.assertEqual(mod.verify_macho(sample(True),sample(False))["cryptid_after"],0)
    def test_reject_changed_code(self):
        b=bytearray(sample(False));b[99]=11
        with self.assertRaises(ValueError):
            mod.verify_macho(sample(True),bytes(b))
    def test_reject_still_encrypted(self):
        with self.assertRaises(ValueError):
            mod.verify_macho(sample(True),sample(True))
    def test_reject_zero_fill(self):
        b=bytearray(sample(False));b[64:96]=bytes(32)
        with self.assertRaises(ValueError):
            mod.verify_macho(sample(True),bytes(b))
if __name__=="__main__":
    unittest.main()

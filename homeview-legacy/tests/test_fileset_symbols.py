import importlib.util
import struct
from pathlib import Path
import tempfile
import unittest

PATH = Path(__file__).resolve().parents[1] / "scripts" / "scan_fileset_symbols.py"
spec = importlib.util.spec_from_file_location("scan_fileset_symbols", PATH)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


def macho_with_symbol(name):
    symbol = b"\x00" + name + b"\x00"
    header = struct.pack("<IIIIIII", 0xFEEDFACF, 0x0100000C, 0, 0xB, 1, 24, 0) + struct.pack("<I", 0)
    symoff = 32 + 24
    stroff = symoff + 16
    command = struct.pack("<IIIIII", 0x2, 24, symoff, 1, stroff, len(symbol))
    nlist = struct.pack("<IBBHQ", 1, 0x0F, 1, 0, 0)
    return header + command + nlist + symbol


class FilesetSymbolTests(unittest.TestCase):
    def test_symbol_and_vtable_are_recorded(self):
        data = macho_with_symbol(b"_ZTV11AFKResource")
        report = mod.scan_image_bytes(data) if hasattr(mod, "scan_image_bytes") else None
        image = mod.inspect_image(data, "AppleFirmwareKit")
        self.assertEqual(image["string_count"], 1)
        self.assertTrue(image["symbol_hits"][0]["is_vtable"])

    def test_fileset_entry_without_macho_magic_is_counted(self):
        # Outer fileset whose only entry points at non-Mach-O bytes.
        name = b"com.example.kext\x00"
        header = struct.pack("<IIIIIII", 0xFEEDFACF, 0x0100000C, 0, 12, 1, 32 + len(name), 0) + struct.pack("<I", 0)
        # fileoff points just past the command, at the name bytes, which are not a macho.
        fileoff = 32 + 32
        command = struct.pack("<IIQQII", 0x80000035, 32 + len(name), 0, fileoff, 32, 0) + name
        blob = header + command
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "bootkc"
            path.write_bytes(blob)
            report = mod.scan(path)
        self.assertEqual(report["fileset_entry_count"], 1)
        self.assertEqual(report["fileset_entries_not_macho"], 1)
        self.assertFalse(report["implementation_found"])


if __name__ == "__main__":
    unittest.main()

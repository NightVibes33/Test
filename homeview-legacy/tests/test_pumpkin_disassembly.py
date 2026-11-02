import importlib.util
import pathlib
import unittest

path = pathlib.Path(__file__).resolve().parents[1] / "scripts" / "analyze_pumpkin_disassembly.py"
spec = importlib.util.spec_from_file_location("analyze_pumpkin_disassembly", path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class DisassemblyTests(unittest.TestCase):
    def test_named_call_is_only_a_hint(self):
        text = """_MobileGestalt_get_pumpkinMode:
0x180123450: pacibsp
0x180123454: adrp x8, #0x180000000
0x180123458: bl #0x180123000 ; _IORegistryEntryCreateCFProperty
0x18012345c: cbz x0, 0x180123478
0x180123460: ret
"""
        actual = module.analyze(text)
        self.assertTrue(actual["instruction_level_disassembly_present"])
        self.assertEqual(actual["direct_call_count"], 1)
        self.assertEqual(actual["symbol_named_source_hints"][0]["source"], "IORegistry")
        self.assertFalse(actual["backing_source_verified"])
        self.assertIsNone(actual["experimental_chosen_property_used_by_apple"])

    def test_encoded_bytes_and_indirect_call(self):
        text = """0x180123450: 5f 24 03 d5 bti c
0x180123454: 20 00 80 d2 mov x0, #1
0x180123458: 00 00 3f d6 blr x0
0x18012345c: c0 03 5f d6 ret"""
        actual = module.analyze(text)
        self.assertTrue(actual["instruction_level_disassembly_present"])
        self.assertEqual(actual["indirect_call_count"], 1)
        self.assertEqual(actual["return_instruction_count"], 1)

    def test_help_or_error_cannot_be_misclassified(self):
        self.assertFalse(module.analyze("Error: unknown flag --x")[
            "instruction_level_disassembly_present"])
        self.assertFalse(module.analyze("Usage: ipsw dyld disass [flags]")[
            "instruction_level_disassembly_present"])

if __name__ == "__main__":
    unittest.main()

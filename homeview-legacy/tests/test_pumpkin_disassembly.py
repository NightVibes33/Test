import importlib.util
import pathlib
import unittest

path = pathlib.Path(__file__).resolve().parents[1] / "scripts" / "analyze_pumpkin_disassembly.py"
spec = importlib.util.spec_from_file_location("analyze_pumpkin_disassembly", path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

REAL_SHAPE = """   • Locating symbol: _MobileGestalt_get_pumpkinMode
_MobileGestalt_get_pumpkinMode:
0x1afe8db50:  7f 23 03 d5   pacibsp
0x1afe8db54:  ff 03 01 d1   sub sp, sp, #0x40
0x1afe8db70:  15 00 80 12   mov w21, #0xffffffff
0x1afe8db74:  f5 0f 00 b9   str w21, [sp, #0xc]
0x1afe8db78:  40 b6 1a d0   adrp x0, 0x1e5557000
0x1afe8db7c:  00 e0 04 91   add x0, x0, #0x138 ; _ptr.__NSCFConstantString
0x1afe8db84:  09 6d ff 97   bl _MGCopyAnswer
0x1afe8db90:  7c 6a 0a 94   bl _CFGetTypeID_stub
0x1afe8db98:  a2 6a 0a 94   bl _CFNumberGetTypeID_stub
0x1afe8db9c:  bf 02 00 eb   cmp x21, x0
0x1afe8dbb0:  a0 6a 0a 94   bl _CFNumberGetValue_stub
0x1afe8dc08:  f5 0f 40 b9   ldr w21, [sp, #0xc]
0x1afe8dc24:  ff 0f 5f d6   retab
_MobileGestalt_get_quickNoteCapability:
0x1afe8dc34: 40 b6 1a d0 adrp x0, 0x1e5557000
0x1afe8dc38: 00 60 05 91 add x0, x0, #0x158
0x1afe8dc3c: 8d 6c ff 17 b _MGGetBoolAnswer
"""


class DisassemblyTests(unittest.TestCase):
    def test_real_getter_is_numeric_mgcopyanswer_wrapper(self):
        found = module.analyze(REAL_SHAPE)
        self.assertEqual(found["getter_implementation_class"],
                         "MGCopyAnswer_wrapped_numeric_answer")
        self.assertTrue(found["minus_one_failure_sentinel_initialized_and_reloaded"])
        self.assertTrue(found["CFNumber_value_requested"])
        self.assertEqual(found["MGCopyAnswer_key_constant_object_pointer"], "0x1e5557138")
        self.assertEqual(found["function_entry"], "0x1afe8db50")
        self.assertEqual(found["instruction_count"], 13)
        self.assertEqual(found["direct_call_count"], 4)
        self.assertFalse(found["backing_source_verified"])
        self.assertFalse(found["homeview_24V514_getter_checked"])

    def test_adjacent_getter_not_counted(self):
        found = module.analyze(REAL_SHAPE +
            "0x1afe8dc40: ff 0f 5f d6 retab\n")
        self.assertEqual(found["direct_call_count"], 4)

    def test_missing_target_not_success(self):
        found = module.analyze("_OtherFunction:\n" +
            REAL_SHAPE.split("_MobileGestalt_get_quickNoteCapability:")[1])
        self.assertFalse(found["instruction_level_disassembly_present"])

    def test_error_or_help_never_verified(self):
        self.assertFalse(module.analyze("Error: unknown flag --x")[
            "instruction_level_disassembly_present"])
        self.assertFalse(module.analyze("Usage: ipsw dyld disass [flags]")[
            "instruction_level_disassembly_present"])

    def test_anonymous_subfunctions_not_part_of_mgcopyanswer(self):
        output = """_MGCopyAnswer:
0x1afe68fa8: 7f 23 03 d5 pacibsp
0x1afe68fb0: fd 7b 01 a9 stp fp, lr, [sp, #0x10]
0x1afe68fbc: 73 fd ff 97 bl _MGGetGlobalCache
0x1afe68fc8: 02 00 80 d2 mov x2, #0
0x1afe68fe4: 19 fe ff 17 b 0x1afe68848
sub_1afe68fe8:
0x1afe68fe8: 40 fe 1e f0 adrp x0, 0x1ede33000
0x1afe68fec: 00 80 29 91 add x0, x0, #0xa60
0x1afe68ff0: 01 00 80 d2 mov x1, #0
0x1afe68ff4: 03 45 0b 14 b _pthread_key_create_stub
"""
        result = module.analyze_resolver(output)
        self.assertEqual(result["instruction_count"], 5)
        self.assertEqual(result["tail_branch_target"], "0x1afe68848")
        self.assertTrue(result["MGGetGlobalCache_called_directly"])
        self.assertFalse(result["actual_resolver_backing_source_verified"])

    def test_followup_rejects_mismatched_start(self):
        output = """sub_1afe68848:
0x1afe68848: 7f 23 03 d5 pacibsp
0x1afe6884c: f4 4f be a9 stp x20, x19, [sp, #-0x20]!
0x1afe68850: 00 00 00 94 bl _CFDictionaryGetValue_stub
_Other:
0x1afe68854: ff 0f 5f d6 retab
"""
        self.assertTrue(module.analyze_followup(output, "0x1afe68848")
                        ["entry_verified_from_original_disassembly"])
        self.assertFalse(module.analyze_followup(output, "0x1afe6884c")
                         ["entry_verified_from_original_disassembly"])

    def test_resolver_cannot_prove_dataflow(self):
        output = """_MGCopyAnswer:
0x180010000: 7f 23 03 d5 pacibsp
0x180010004: 00 00 00 94 bl _IORegistryEntryCreateCFProperty
0x180010008: 00 00 3f d6 blr x0
0x18001000c: ff 0f 5f d6 retab
_Other:
0x180020000: ff 0f 5f d6 retab
"""
        found = module.analyze_resolver(output)
        self.assertEqual(found["instruction_count"], 4)
        self.assertEqual(found["named_callsite_hints"][0]["source"], "IORegistry")
        self.assertFalse(found["actual_resolver_backing_source_verified"])


if __name__ == "__main__":
    unittest.main()

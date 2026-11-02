import importlib.util
from pathlib import Path
import unittest

BASE = Path(__file__).resolve().parents[1]
PATH = BASE / "scripts" / "original_pc_signatures.py"
spec = importlib.util.spec_from_file_location("original_pc_signatures", PATH)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


def fake(klass, address, words):
    return {"class": klass, "vtable_slot": 85, "address": address,
            "requested_vaddr_is_first_instruction": True,
            "assembly_excerpt": [
                f"0x{int(address,16)+4*i:x}:  " +
                " ".join(f"{b:02x}" for b in word) + "   mov x0, x1"
                for i, word in enumerate(words)]}


class SignatureTests(unittest.TestCase):
    def test_12_words_separates_ans2_and_ans3_first_8_identical(self):
        shared = [bytes([0x7f, 0x23, 0x03, 0xd5])] * 11
        first = fake("AppleANS2CGv2Controller", "0xfffffff009b1d1e4",
                     shared + [bytes([0xff, 0x17, 0x00, 0xf9])])
        second = fake("AppleANS3CGv2Controller", "0xfffffff009b0dabc",
                      shared + [bytes([0xff, 0x2f, 0x00, 0xb9])])
        records = mod.from_disassembly({"targets": [first, second]})
        self.assertEqual(len(records), 2)
        self.assertEqual(len(records[0]["signature_hex"]), 96)
        self.assertNotEqual(records[0]["signature_hex"], records[1]["signature_hex"])
        self.assertEqual(len(mod.plugin_args({"targets": [first, second]})), 2)

    def test_duplicate_or_truncated_fingerprints_not_used(self):
        words = [bytes([0xff, 0x03, 0x02, 0xd1])] * 12
        a = fake("A", "0xfffffff009b1d1e4", words)
        b = fake("B", "0xfffffff009b0dabc", words)
        self.assertEqual(mod.from_disassembly({"targets":[a, b]}), [])
        self.assertEqual(mod.from_disassembly({"targets":[
            fake("A", "0xfffffff009b1d1e4", words[:11])]}), [])

    def test_invalid_original_alignment_fails_closed(self):
        a = fake("A", "0xfffffff009b1d1e4",
                 [bytes([0xff, 0x03, 0x02, 0xd1])] * 12)
        a["assembly_excerpt"][1] = "0xfffffff009b1d1f4: ff 03 02 d1 sub"
        self.assertEqual(mod.from_disassembly({"targets":[a]}), [])


if __name__ == "__main__":
    unittest.main()

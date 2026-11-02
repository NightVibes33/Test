import importlib.util
from pathlib import Path
import unittest

P = Path(__file__).resolve().parents[1] / "scripts" / "analyze_original_ans2_callgraph.py"
spec = importlib.util.spec_from_file_location("analyze_original_ans2_callgraph", P)
a = importlib.util.module_from_spec(spec)
spec.loader.exec_module(a)

def item(klass, slot, lines, verified=True):
    return {"class": klass, "vtable_slot": slot,
            "address": "0xfffffff009b0dabc",
            "requested_vaddr_is_first_instruction": verified,
            "assembly_excerpt": lines}


class OriginalANSCallgraphTests(unittest.TestCase):
    def test_shared_original_bl_from_ans2_and_ans3(self):
        report = a.analyze({"targets": [
            item("AppleANS3CGv2Controller", 85, [
                "0xfffffff009b0db6c:  28 56 00 94   bl 0xfffffff009b2340c"]),
            item("AppleANS2CGv2Controller", 85, [
                "0xfffffff009b1d294:  5e 18 00 94   bl 0xfffffff009b2340c"]),
            item("RTBuddy", 86, [
                "0xfffffff00a1112cc:  af be 00 94   bl 0xfffffff00a140d88"]),
        ]})
        shared = report["shared_direct_call_targets"]
        self.assertEqual(len(shared), 1)
        self.assertEqual(shared[0]["destination"], "0xfffffff009b2340c")
        self.assertEqual(shared[0]["distinct_calling_classes"],
                         ["AppleANS2CGv2Controller", "AppleANS3CGv2Controller"])
        self.assertFalse(shared[0]["function_semantics_proven"])
        self.assertFalse(report["ANS2_controller_successful_start_proven"])

    def test_unverified_disassembly_does_not_create_calls(self):
        d = a.analyze({"targets": [item(
            "AppleANS2CGv2Controller", 85,
            ["0xfffffff009b1d294: bl 0xfffffff009b2340c"], False)]})
        self.assertFalse(d["analyzed_original_vtable_entries"][0]["verified_entry"])
        self.assertEqual(d["shared_direct_call_targets"], [])

    def test_indirect_calls_distinguished(self):
        got = a.extract_calls(item("RTBuddy", 86, [
            "0xfffffff00a111200:  00 02 3f d6   blr x16",
            "0xfffffff00a111204:  00 00 00 94   bl 0xfffffff009ff0000"]))
        self.assertEqual(got["indirect_call_count"], 1)
        self.assertEqual(len(got["direct_calls"]), 1)

    def test_never_invents_names_or_runtime_handshake(self):
        got = a.analyze({"targets": []})
        self.assertEqual(got["shared_direct_call_targets"], [])
        self.assertFalse(got["target_name_or_purpose_inferred"])
        self.assertFalse(got["RTBuddy_firmware_handshake_proven"])


if __name__ == "__main__":
    unittest.main()

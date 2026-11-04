import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "scripts" / "homeview_tcg_pc_trace.c"
PROBE = ROOT / "scripts" / "probe_homeview_boot.py"
DISASS = ROOT / "scripts" / "disassemble_ans2_vtables.py"
spec = importlib.util.spec_from_file_location("disassemble_ans2_vtables", DISASS)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


class TCGPCPluginTests(unittest.TestCase):
    def test_pinned_plugin_v7_callback_contract(self):
        source = SRC.read_text()
        self.assertIn("QEMU_PLUGIN_VERSION", source)
        self.assertIn("qemu_plugin_insn_vaddr(insn)", source)
        self.assertIn("qemu_plugin_register_vcpu_insn_exec_cb", source)
        self.assertIn("qemu_plugin_register_vcpu_tb_trans_cb", source)
        self.assertIn("qemu_plugin_read_memory_vaddr", source)
        self.assertIn("HOMEVIEW_TCG_PC_TRACE_FILE", source)
        self.assertIn("candidate_budget_exhausted=true", source)
        self.assertIn("complete_in_tb", source)
        self.assertIn("exec_callback_fired", source)
        self.assertIn("classification=no_hit_instrumentation_active", source)
        self.assertIn("hv_prefix_kind", source)
        self.assertIn("qemu_plugin_register_atexit_cb", source)
        self.assertIn("note_slide_vote", source)
        self.assertIn("witness_signatures=", source)
        self.assertIn("basis=executed_distinct_fingerprints", source)
        self.assertIn("slid_pc_hit static=", source)
        self.assertIn("targets[j].address == addr - slide", source)
        self.assertIn("distinct >= 2", source)
        self.assertNotIn("volatile int hooked;", source)
        self.assertIn("QEMU_PLUGIN_CB_NO_REGS", source)
        self.assertIn("__sync_bool_compare_and_swap", source)
        self.assertNotIn("qemu_plugin_set_pc(", source)
        self.assertNotIn("qemu_plugin_write_memory", source)

    def test_only_original_apple_addresses_selected(self):
        classes = {"class_inspection": {
            "AppleANS3CGv2Controller": {"inspection_completed": True,
                "class_defined_vtable_slot_sample": [
                    {"slot":85,"target":"0xfffffff009b0dabc",
                     "vtable_offset":"0x2a8"}]}}}
        target = mod.select_targets(classes)
        self.assertEqual(len(target), 1)
        self.assertEqual(target[0]["address"], "0xfffffff009b0dabc")

    def test_guest_probe_uses_isolated_variant(self):
        code = PROBE.read_text()
        self.assertIn('HOMEVIEW_TCG_PC_PLUGIN', code)
        self.assertIn('select_targets', code)
        self.assertIn('original_pc_signatures', code)
        self.assertIn('shared_call_pcs', code)
        self.assertIn('homeview-original-ans2-shared-calls.json', code)
        self.assertIn('experimental_shared_direct_BL_trace_targets', code)
        self.assertIn('fingerprint_args', code)
        self.assertIn('if name == "software-update-ans-binding-probe":', code)
        self.assertIn('argv[argv.index("-d") + 1] += ",plugin"', code)

    def test_deterministic_fingerprint_selftest(self):
        with tempfile.TemporaryDirectory() as temp:
            binary = Path(temp) / "hv-selftest"
            trace = Path(temp) / "trace.log"
            subprocess.check_call([
                "cc", "-std=c11", "-Wall", "-Wextra", "-Werror",
                "-DHOMEVIEW_FINGERPRINT_SELFTEST", "-o", str(binary), str(SRC)])
            completed = subprocess.run([str(binary), str(trace)],
                                       check=True, capture_output=True, text=True)
            text = completed.stdout
            self.assertIn("PASS POSITIVE full", text)
            self.assertIn("PASS NEGATIVE single-byte mutation", text)
            self.assertIn("PASS CROSS_TB prefix", text)
            self.assertIn("PASS CROSS_TB short prefix rejected", text)
            self.assertIn("PASS CROSS_TB tail mutation", text)
            self.assertIn("PASS RELOCATION aligned slide", text)
            self.assertIn("PASS RELOCATION unaligned rejected", text)
            self.assertIn("execution=false", text)
            self.assertIn("phase=executed", text)
            self.assertIn("classification=no_hit_instrumentation_active", text)
            saved = trace.read_text()
            self.assertIn("HOMEVIEW_PC_TRACE initialized", saved)
            self.assertIn("execution=false", saved)
            self.assertIn("phase=executed", saved)
            self.assertIn("classification=hits_recorded", saved)
            self.assertNotIn("execution=false", saved.split("fingerprint_hit", 1)[1].split("\n", 1)[0])

if __name__ == "__main__":
    unittest.main()

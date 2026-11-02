import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest

path=Path(__file__).resolve().parents[1]/"scripts"/"disassemble_ans2_vtables.py"
spec=importlib.util.spec_from_file_location("disassemble_ans2_vtables",path)
mod=importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


class OriginalAppleVtableDisassembly(unittest.TestCase):
    def classes(self):
        return {"class_inspection": {
            "AppleANS3CGv2Controller": {
                "inspection_completed": True,
                "class_defined_vtable_slot_sample": [
                    {"slot":85,"target":"0xfffffff009b0dabc","vtable_offset":"0x2a8"},
                    {"slot":260,"target":"0xfffffff009ad026c","vtable_offset":"0x820"}]},
            "AppleANS2CGv2Controller": {"inspection_completed": False},
            "RTBuddy": {"inspection_completed": True,
                        "class_defined_vtable_slot_sample": [
                            {"slot":86,"target":"0xfffffff00a1112a0","vtable_offset":"0x2b0"}]},
        }}

    def test_select_only_actual_original_class_slots(self):
        selection=mod.select_targets(self.classes())
        self.assertEqual(len(selection),3)
        self.assertEqual(selection[0]["vtable_slot"],85)
        self.assertEqual(selection[1]["vtable_slot"],260)
        self.assertEqual(selection[2]["fileset_entry"],"com.apple.driver.RTBuddy")
        self.assertNotIn("AppleANS2CGv2Controller",[x["class"] for x in selection])

    def test_correct_fileset_vaddr_command_and_vaddr_proof(self):
        with tempfile.TemporaryDirectory() as tmp:
            image=Path(tmp)/"kernelcache";image.write_bytes(b"K"*8192)
            calls=[]
            def fake(args,**kwargs):
                calls.append(args)
                self.assertEqual(args[1:3],["macho","disass"])
                self.assertEqual(args[args.index("--count")+1],"48")
                entry=args[args.index("--vaddr")+1]
                return subprocess.CompletedProcess(args,0,
                      (entry+": deadbeef mov x0, x1\n").encode())
            result=mod.analyze(self.classes(), image, fake)
            self.assertEqual(result["selected_vtable_target_count"],3)
            self.assertTrue(all(x["requested_vaddr_is_first_instruction"]
                                for x in result["targets"]))
            self.assertFalse(result["Apple_ANS_NVMe_controller_start_confirmed"])
            self.assertFalse(result["kernelcache_executable_in_report"])

    def test_failed_or_wrong_disassembly_never_claims_success(self):
        with tempfile.TemporaryDirectory() as tmp:
            image=Path(tmp)/"kernelcache";image.write_bytes(b"K"*8192)
            def fake(args,**kwargs):
                return subprocess.CompletedProcess(args,0,b"0xfffffff009b0dabe: wrong\n")
            res=mod.analyze(self.classes(),image,fake)
            self.assertFalse(any(x["requested_vaddr_is_first_instruction"]
                                 for x in res["targets"]))

    def test_does_not_invent_missing_addresses(self):
        bad=self.classes()
        bad["class_inspection"]["RTBuddy"]["class_defined_vtable_slot_sample"][0]["target"]="0xwrong"
        self.assertEqual(len(mod.select_targets(bad)),2)

    def test_kernelcache_is_required(self):
        with tempfile.TemporaryDirectory() as d:
            with self.assertRaises(ValueError):
                mod.analyze(self.classes(),Path(d)/"missing")


if __name__ == "__main__":
    unittest.main()

import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest

p=Path(__file__).resolve().parents[1]/"scripts"/"inspect_original_iokit_classes.py"
spec=importlib.util.spec_from_file_location("inspect_original_iokit_classes", p)
mod=importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


class AppleKernelCppTests(unittest.TestCase):
    def test_bounded_no_runtime_claim(self):
        text="\n".join(["AppleANS2NVMeController::start 0xfffffe0012345000"]*150)
        rec=mod.normalize_text(text)
        self.assertEqual(rec["total_lines"], 150)
        self.assertEqual(len(rec["sample_lines"]), 110)
        self.assertTrue(rec["output_truncated"])
        self.assertEqual(rec["addresses_observed"], ["0xfffffe0012345000"])

    def test_real_cli_contract_with_fake_runner(self):
        with tempfile.TemporaryDirectory() as temp:
            image=Path(temp)/"kernelcache"
            image.write_bytes(b"\xcf\xfa\xed\xfe"+b"\x00"*5000)
            seen=[]
            def mock(args, **kwargs):
                seen.append(args)
                self.assertEqual(args[1:3], ["kernel", "cpp"])
                self.assertEqual(kwargs["timeout"], mod.TIMEOUT)
                return subprocess.CompletedProcess(
                    args, 0, b"AppleANS2NVMeController::start 0xfffffe000abc1234\n")
            x=mod.inspect(image,runner=mock)
            self.assertEqual(len(seen), len(mod.CLASSES))
            self.assertTrue(x["class_inspection"]["RTBuddy"]["inspection_completed"])
            self.assertFalse(x["ANS2_RTKit_or_NVMe_service_started"])
            self.assertFalse(x["original_kernelcache_binary_included"])

    def test_failed_cli_is_not_class_proof(self):
        with tempfile.TemporaryDirectory() as tmp:
            img=Path(tmp)/"k"
            img.write_bytes(b"\x00"*5000)
            def fail(args,**kwargs):
                return subprocess.CompletedProcess(args,1,b"unknown command")
            result=mod.inspect(img,runner=fail)
            self.assertFalse(result["class_inspection"]["AppleASCWrapV6"]["inspection_completed"])

    def test_class_specific_slots_after_first_110_lines_are_recovered(self):
        rows = ["[  %d] +0x%04x 0xfffffff008000000 -> 0xfffffff00a111111 "
                "A--- key=0 pac=0x3771 IOService::fn_0x%x()" % (i, i*8, i*8)
                for i in range(150)]
        rows.append("[200] +0x0640 0xfffffff008000000 -> 0xfffffff00a222222 "
                    "AO-- key=0 pac=0x3771 AppleANS3CGv2Controller::fn_0x640()")
        evidence = mod.normalize_text("\n".join(rows),
                                      "AppleANS3CGv2Controller")
        self.assertTrue(evidence["output_truncated"])
        self.assertEqual(evidence["class_defined_vtable_slots_observed"], 1)
        self.assertEqual(
            evidence["class_defined_vtable_slot_sample"][0]["target"],
            "0xfffffff00a222222")
        self.assertFalse(evidence["class_defined_vtable_slot_sample"][0][
            "disassembled_method_or_runtime_call_verified"])

    def test_highest_scored_ans3_cgv2_class_is_inspected(self):
        self.assertIn("AppleANS3CGv2Controller", mod.CLASSES)
        self.assertIn("AppleANS2CGv2Controller", mod.CLASSES)
        self.assertIn("AppleANS2CGNVMeController", mod.CLASSES)

    def test_no_kernelcache_is_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaisesRegex(ValueError, "unavailable"):
                mod.inspect(Path(tmp)/"none")


if __name__ == "__main__":
    unittest.main()

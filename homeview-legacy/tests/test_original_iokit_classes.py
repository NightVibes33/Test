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

    def test_no_kernelcache_is_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaisesRegex(ValueError, "unavailable"):
                mod.inspect(Path(tmp)/"none")


if __name__ == "__main__":
    unittest.main()

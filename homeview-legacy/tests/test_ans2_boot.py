import importlib.util
from pathlib import Path
import tempfile
import unittest

P = Path(__file__).resolve().parents[1] / "scripts" / "analyze_ans2_boot.py"
SPEC = importlib.util.spec_from_file_location("analyze_ans2_boot", P)
a = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(a)

PROBES = """RTBuddy(ANS2): start(<ptr>) - (Oct 13 2026@19:09:35)
virtual IOService *AppleANS2CGv2Controller::probe(IOService *, SInt32 *)::103:Found (ANS2) provider and coastguard, returning score 400000
virtual IOService *AppleANS2NVMeController::probe(IOService *, SInt32 *)::251:Found (ANS2) provider, returning score 100000
virtual IOService *AppleANS3CGv2Controller::probe(IOService *, SInt32 *)::97:Found (ANS2) provider and coastguard, returning score 500000
virtual IOService *AppleANS3NVMeController::probe(IOService *, SInt32 *)::82:Found (ANS2) provider and linear-sq, returning score 300000
Waiting for NAND service to publish
"""
QEMU = """HOMEVIEW_MMIO_TRACE installed arm-io/ans base=0x389600000 length=0x88000 index=0
HOMEVIEW_MMIO_TRACE installed arm-io/sart-ans base=0x38dc50000 length=0x4000 index=0
"""


class ANS2BootTests(unittest.TestCase):
    def test_real_guest_format_rtbuddy_and_probes_not_controller_start(self):
        report = a.compare("no service", PROBES, QEMU)
        trial = report["original_ANS_compatible_experiment"]
        self.assertEqual(report["result"],
                         "original_compatibility_enables_ANS2_RTBuddy_probe_path")
        self.assertTrue(trial["ANS2_RTBuddy_start_was_invoked"])
        self.assertEqual(trial["ANS_controller_probe_count"], 4)
        self.assertEqual(trial["highest_scored_candidate"], "AppleANS3CGv2Controller")
        self.assertFalse(trial["highest_score_proves_winning_driver"])
        self.assertFalse(trial["ANS_controller_start_observed"])
        self.assertEqual(trial["NAND_service_wait_count"], 1)
        self.assertFalse(trial["NAND_service_publish_logged"])
        self.assertTrue(report["experimental_QEMU_MMIO"]["ANS_primary_544KiB_window_mapped"])
        self.assertEqual(report["experimental_QEMU_MMIO"]["ANS_or_SART_MMIO_access_count"], 0)
        self.assertFalse(report["functional_ANS2_device_verified"])

    def test_controller_start_requires_explicit_runtime_message(self):
        result = a.observe_serial(PROBES + "AppleANS3CGv2Controller::start(<ptr>)\n")
        self.assertTrue(result["ANS_controller_start_observed"])
        self.assertEqual(result["ANS_controller_start_methods_logged"],
                         ["AppleANS3CGv2Controller"])

    def test_repeated_probes_are_not_winning_class_proof(self):
        result = a.observe_serial(PROBES
            + "AppleANS3NVMeController::probe(xx): returning score 800000\n")
        self.assertEqual(result["ANS_controller_probe_count"], 5)
        self.assertEqual(result["highest_scored_candidate"], "AppleANS3NVMeController")
        self.assertFalse(result["highest_score_proves_winning_driver"])

    def test_absent_log_does_not_prove_no_matching(self):
        result = a.compare("", "", "")
        self.assertEqual(result["result"], "incomplete_guest_log_pair")
        self.assertFalse(result["original_ANS_compatible_experiment"]["ANS2_RTBuddy_start_was_invoked"])

    def test_mmio_access_is_not_a_real_storage_controller(self):
        log = QEMU + "HOMEVIEW_MMIO_TRACE write arm-io/ans off=0x28100 value=0x1 size=4 index=0\n"
        data = a.observe_qemu(log)
        self.assertEqual(data["ANS_or_SART_MMIO_access_count"], 1)
        self.assertTrue(data["QEMU_MMIO_zero_return_stubs_are_not_hardware_emulation"])

    def test_bounded_log_reader(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "input.log"
            self.assertEqual(a.read_limited(path), "")
            path.write_text("x" * 60)
            before = a.MAX_LOG
            try:
                a.MAX_LOG = 50
                with self.assertRaisesRegex(ValueError, "exceeds"):
                    a.read_limited(path)
            finally:
                a.MAX_LOG = before


if __name__ == "__main__":
    unittest.main()

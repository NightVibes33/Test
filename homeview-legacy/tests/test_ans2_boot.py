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

    def test_tcg_program_counter_hit_proves_dispatch_only(self):
        log = QEMU + (
            "HOMEVIEW_PC_TRACE initialized targets=2 read_only=true\n"
            "HOMEVIEW_PC_TRACE hit target=0xfffffff009b0dabc cpu=0\n")
        result = a.observe_qemu(log)
        self.assertTrue(result["PC_trace_plugin_initialized"])
        self.assertEqual(result["observed_guest_PC_hits"][0]["target_vaddr"],
                         "0xfffffff009b0dabc")
        self.assertTrue(result["PC_hit_proves_dispatch_not_method_completion"])
        self.assertTrue(result["no_PC_hits_does_not_exclude_KASLR_or_missing_targets"])

    def test_pc_hits_from_serial_and_qemu_are_deduplicated(self):
        original = "original control"
        guest = PROBES + "HOMEVIEW_PC_TRACE hit target=0xfffffff009b0dabc cpu=0\n"
        trace = QEMU + (
            "HOMEVIEW_PC_TRACE initialized targets=2 read_only=true\n"
            "HOMEVIEW_PC_TRACE hit target=0xfffffff009b0dabc cpu=0\n")
        result = a.compare(original, guest, trace)
        qemu = result["experimental_QEMU_MMIO"]
        self.assertTrue(qemu["PC_trace_plugin_initialized"])
        self.assertEqual(qemu["PC_hit_count"], 1)
        self.assertEqual(qemu["observed_guest_PC_hits"][0]["cpu"], 0)
        self.assertFalse(result["functional_ANS2_device_verified"])

    def test_sld_original_code_fingerprint_at_guest_vaddr(self):
        log = (QEMU + "HOMEVIEW_PC_TRACE fingerprint_hit "
               "static=0xfffffff009b0dabc guest=0xfffffff109b0dabc cpu=0\n")
        observed = a.compare("baseline guest", PROBES, log)
        fingerprints = observed["experimental_QEMU_MMIO"]["original_code_fingerprint_hits"]
        self.assertEqual(len(fingerprints), 1)
        self.assertNotEqual(fingerprints[0]["static_vaddr"],
                            fingerprints[0]["runtime_guest_vaddr"])
        self.assertFalse(observed["functional_ANS2_device_verified"])

    def test_independent_pc_log_still_parses_without_qemu_debug_mask(self):
        pc = ("HOMEVIEW_PC_TRACE initialized targets=8 signatures=8 read_only=true\n"
              "HOMEVIEW_PC_TRACE fingerprint_hit static=0xfffffff009b0dabc "
              "guest=0xfffffff109b0dabc cpu=0 mode=cross-tb\n")
        result = a.compare("control", PROBES, "", pc)
        observed = result["experimental_QEMU_MMIO"]
        self.assertTrue(observed["independent_PC_trace_file_present"])
        self.assertTrue(observed["independent_PC_trace_initialized"])
        self.assertEqual(observed["original_code_fingerprint_hit_count"], 1)
        self.assertFalse(observed["zero_hits_are_inconclusive"])
        self.assertFalse(result["functional_ANS2_device_verified"])

    def test_candidate_budget_exhaustion_prohibits_zero_hit_conclusion(self):
        trace = ("HOMEVIEW_PC_TRACE initialized targets=8 signatures=8 read_only=true\n"
                 "HOMEVIEW_PC_TRACE candidate_budget_exhausted=true no_hit_is_inconclusive=true\n")
        report = a.compare("control", PROBES, "", trace)
        self.assertTrue(report["experimental_QEMU_MMIO"]["zero_hits_are_inconclusive"])
        self.assertTrue(report["experimental_QEMU_MMIO"]["PC_trace_candidate_budget_exhausted"])

    def test_historical_hits_share_one_slide_and_flag_the_outlier(self):
        log = (
            "HOMEVIEW_PC_TRACE initialized targets=8 signatures=8 read_only=true\n"
            "HOMEVIEW_PC_TRACE fingerprint_hit static=0xfffffff009afa1bc "
            "guest=0xfffffff02a35b730 cpu=0\n"
            "HOMEVIEW_PC_TRACE fingerprint_hit static=0xfffffff00a1112a0 "
            "guest=0xfffffff02a1112a0 cpu=0\n"
            "HOMEVIEW_PC_TRACE fingerprint_hit static=0xfffffff009b1d1e4 "
            "guest=0xfffffff029b1d1e4 cpu=0\n"
            "HOMEVIEW_PC_TRACE fingerprint_hit static=0xfffffff009b0dabc "
            "guest=0xfffffff029b0dabc cpu=0\n")
        report = a.compare(
            "no service",
            PROBES + "unable to get framebuffer\nCouldn't alloc class \"AFKResource\"\n",
            log)
        qemu = report["experimental_QEMU_MMIO"]
        self.assertEqual(qemu["kernelcache_slide_consensus"], "0x20000000")
        self.assertEqual(qemu["original_code_fingerprint_hit_count"], 4)
        off = [hit for hit in qemu["original_code_fingerprint_hits"]
               if not hit["on_consensus_kernelcache_slide"]]
        self.assertEqual(len(off), 1)
        self.assertEqual(off[0]["static_vaddr"], "0xfffffff009afa1bc")
        self.assertEqual(report["storage_stop"],
                         "probe_scores_logged_controller_start_absent_no_ANS_MMIO")
        self.assertEqual(report["framebuffer_stop"],
                         "userspace_display_service_missing_no_DCP_MMIO")
        self.assertFalse(report["functional_ANS2_device_verified"])
        self.assertFalse(report["normal_installed_HomeView_or_BreadBoard_boot_verified"])
        self.assertTrue(report["AFKResource_alloc_failed_before_controller_start"])
        self.assertEqual(report["display_provider_stop"], "DCP_RTBuddy_start_not_logged")

    def test_dcp_nub_without_region_is_not_a_dram_carve(self):
        window = a.dcp_firmware_window({
            "nodes": [{
                "path": "/device-tree/arm-io/dcp/iop-dcp-nub",
                "property_names": ["no-firmware-service", "quiesced", "compatible"],
            }],
        })
        self.assertTrue(window["no_firmware_service"])
        self.assertFalse(window["region_base_property_present"])
        self.assertFalse(window["dram_carve_applicable"])
        self.assertIn("AFKResource", window["reason"])

    def test_active_instrumentation_with_no_hit_is_not_a_storage_success(self):
        trace = (
            "HOMEVIEW_PC_TRACE initialized targets=8 signatures=8 read_only=true\n"
            "HOMEVIEW_PC_TRACE exec_callback_fired cpu=0 guest=0x1000 seq=1 time_ns=1\n"
            "HOMEVIEW_PC_TRACE summary translations=3 exec_callbacks=1 "
            "fingerprint_hits=0 exact_pc_hits=0 instrumentation_active=true "
            "classification=no_hit_instrumentation_active\n")
        report = a.compare("control", "Waiting for NAND service to publish\n", "", trace)
        qemu = report["experimental_QEMU_MMIO"]
        self.assertTrue(qemu["exec_callbacks_confirmed"])
        self.assertTrue(qemu["configured_fingerprints_absent_while_instrumentation_active"])
        self.assertEqual(qemu["original_code_fingerprint_hit_count"], 0)
        self.assertFalse(qemu["zero_hits_are_inconclusive"])
        self.assertFalse(report["functional_ANS2_device_verified"])
        self.assertNotEqual(report["storage_stop"],
                            "probe_scores_logged_controller_start_absent_no_ANS_MMIO")

    def test_class_and_slot_survive_trace_parse(self):
        trace = (
            "HOMEVIEW_PC_TRACE fingerprint_hit static=0xfffffff000001000 "
            "guest=0xfffffff020001000 cpu=0 mode=cross-tb class=TestController "
            "slot=85 seq=2 time_ns=20 slide=0x20000000 phase=executed\n")
        observed = a.observe_qemu(trace)
        hit = observed["original_code_fingerprint_hits"][0]
        self.assertEqual(hit["class"], "TestController")
        self.assertEqual(hit["vtable_slot"], 85)
        self.assertEqual(hit["mode"], "cross-tb")
        self.assertEqual(hit["kernelcache_slide"], "0x20000000")
        self.assertEqual(observed["DCP_or_SGX_MMIO_access_count"], 0)

    def test_learned_kaslr_slide_and_exact_slid_branch_execution(self):
        trace = (
            "HOMEVIEW_PC_TRACE initialized targets=11 signatures=8 read_only=true\n"
            "HOMEVIEW_PC_TRACE fingerprint_hit static=0xfffffff00a1112a0 "
            "guest=0xfffffff02a1112a0 cpu=0 mode=full-tb class=RTBuddy slot=86\n"
            "HOMEVIEW_PC_TRACE fingerprint_hit static=0xfffffff009b1d1e4 "
            "guest=0xfffffff029b1d1e4 cpu=0 mode=full-tb class=AppleANS2CGv2Controller slot=85\n"
            "HOMEVIEW_PC_TRACE slide_consensus slide=0x20000000 "
            "witness_signatures=2 basis=executed_distinct_fingerprints seq=12 time_ns=77\n"
            "HOMEVIEW_PC_TRACE slid_pc_hit static=0xfffffff009b2340c "
            "guest=0xfffffff029b2340c cpu=0 slide=0x20000000 "
            "seq=13 time_ns=88 phase=executed\n"
        )
        qemu = a.compare("control", PROBES, "", trace)["experimental_QEMU_MMIO"]
        self.assertEqual(qemu["kernelcache_slide_consensus"], "0x20000000")
        self.assertEqual(qemu["fingerprint_hits_on_consensus_slide"], 2)
        self.assertEqual(qemu["relocated_guest_PC_hit_count"], 1)
        self.assertTrue(qemu["slid_PC_hits_agree_with_fingerprint_consensus"])
        self.assertTrue(qemu["runtime_slide_events_agree_with_fingerprints"])
        self.assertEqual(qemu["runtime_slide_consensus_events"][0]["witness_signatures"], 2)
        self.assertEqual(qemu["relocated_guest_PC_hits"][0]["static_vaddr"],
                         "0xfffffff009b2340c")

    def test_one_signature_or_duplicate_cannot_confirm_a_kernel_slide(self):
        one = [{
            "static_vaddr": "0xfffffff009b0dabc",
            "runtime_guest_vaddr": "0xfffffff029b0dabc",
            "kernelcache_slide": "0x20000000",
        }]
        self.assertIsNone(a.consensus_slide(one))
        self.assertIsNone(a.consensus_slide(one + [dict(one[0])]))
        self.assertNotIn("on_consensus_kernelcache_slide", one[0])

    def test_conflicting_slid_pc_witness_fails_validation(self):
        trace = (
            "HOMEVIEW_PC_TRACE fingerprint_hit static=0xfffffff00a1112a0 "
            "guest=0xfffffff02a1112a0 cpu=0\n"
            "HOMEVIEW_PC_TRACE fingerprint_hit static=0xfffffff009b0dabc "
            "guest=0xfffffff029b0dabc cpu=0\n"
            "HOMEVIEW_PC_TRACE slid_pc_hit static=0xfffffff009b2340c "
            "guest=0xfffffff039b2340c cpu=0 slide=0x30000000\n"
        )
        qemu = a.compare("control", PROBES, "", trace)["experimental_QEMU_MMIO"]
        self.assertFalse(qemu["slid_PC_hits_agree_with_fingerprint_consensus"])

    def test_preconsensus_execution_reconciled_only_after_two_distinct_signatures(self):
        early = (
            "HOMEVIEW_PC_TRACE provisional_pc_hit static=0xfffffff009b2340c "
            "guest=0xfffffff029b2340c cpu=0 slide=0x20000000 "
            "phase=executed validation=pending_fingerprint_consensus\n"
        )
        no_witness = a.compare("control", PROBES, "", early)["experimental_QEMU_MMIO"]
        self.assertEqual(no_witness["preconsensus_candidate_execution_count"], 1)
        self.assertEqual(no_witness["retrospective_confirmed_PC_hit_count"], 0)
        two = early + (
            "HOMEVIEW_PC_TRACE fingerprint_hit static=0xfffffff00a1112a0 "
            "guest=0xfffffff02a1112a0 cpu=0\n"
            "HOMEVIEW_PC_TRACE fingerprint_hit static=0xfffffff009b1d1e4 "
            "guest=0xfffffff029b1d1e4 cpu=0\n"
        )
        report = a.compare("control", PROBES, "", two)
        q = report["experimental_QEMU_MMIO"]
        self.assertEqual(q["kernelcache_slide_consensus"], "0x20000000")
        self.assertEqual(q["retrospective_confirmed_PC_hit_count"], 1)
        self.assertEqual(q["retrospective_confirmed_PC_hits"][0]["static_vaddr"],
                         "0xfffffff009b2340c")
        self.assertTrue(q["early_target_code_executed_before_proven_slide"])
        self.assertFalse(report["functional_ANS2_device_verified"])

    def test_provisional_wrong_slide_remains_unconfirmed_and_budget_incomplete(self):
        trace = (
            "HOMEVIEW_PC_TRACE provisional_pc_hit static=0xfffffff009b2340c "
            "guest=0xfffffff039b2340c cpu=0 slide=0x30000000\n"
            "HOMEVIEW_PC_TRACE fingerprint_hit static=0xfffffff00a1112a0 "
            "guest=0xfffffff02a1112a0 cpu=0\n"
            "HOMEVIEW_PC_TRACE fingerprint_hit static=0xfffffff009b1d1e4 "
            "guest=0xfffffff029b1d1e4 cpu=0\n"
            "HOMEVIEW_PC_TRACE speculative_hook_budget_exhausted=true "
            "retrospective_evidence_incomplete=true\n"
        )
        q = a.compare("control", PROBES, "", trace)["experimental_QEMU_MMIO"]
        self.assertEqual(q["retrospective_confirmed_PC_hit_count"], 0)
        self.assertTrue(q["retrospective_evidence_incomplete"])
        self.assertTrue(q["zero_hits_are_inconclusive"])

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

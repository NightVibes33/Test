import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

path = Path(__file__).resolve().parents[1] / "scripts" / "analyze_j490_kexts.py"
spec = importlib.util.spec_from_file_location("analyze_j490_kexts", path)
a = importlib.util.module_from_spec(spec)
spec.loader.exec_module(a)


class KernelcacheMatchingTests(unittest.TestCase):
    def test_apple_ans2_candidate_not_actual_service_binding(self):
        raw = [
            {"id": "com.apple.driver.AppleANS2", "version": "123",
             "io_kit_personalities": {
                 "AppleANS2": {"IOProviderClass": "IOPlatformDevice",
                               "IONameMatch": "ans", "IOClass": "AppleANS2",
                               "IOProbeScore": 800}}},
            {"id": "com.apple.driver.AppleDCP", "io_kit_personalities": {}},
            {"id": "com.apple.driver.Unrelated", "io_kit_personalities": {}},
        ]
        adt = {"ANS_original_firmware_capabilities": {
            "role": {"present": True, "kind": "text", "value": "ANS2"}}}
        result = a.summarize(raw, adt)
        self.assertEqual(result["parsed_KEXT_records"], 3)
        self.assertEqual(result["matched_KEXT_count"], 2)
        self.assertEqual(result["original_Apple_J490_ANS_identity"]["role"]["value"], "ANS2")
        p = result["matching_storage_graphics_RTKit_KEXTs"][0]["matching_personalities"][0]
        self.assertEqual(p["selectors"]["IONameMatch"], "ans")
        self.assertFalse(result["runtime_driver_loaded_or_start_success_proven"])

    def test_personality_can_make_unrelated_bundle_relevant(self):
        raw = [{"id": "com.apple.driver.bridge", "io_kit_personalities": {
            "SART bridge": {"IOClass": "Bridge"}}}]
        self.assertEqual(a.summarize(raw)["matched_KEXT_count"], 1)

    def test_malformed_unsupported_outputs_are_not_success(self):
        with tempfile.TemporaryDirectory() as d:
            bad = Path(d) / "bad.json"
            bad.write_text("not json")
            self.assertFalse(a.report(bad, Path(d) / "none", 0)["listing_success"])
            self.assertFalse(a.report(bad, Path(d) / "none", 125)["listing_success"])
            with self.assertRaisesRegex(ValueError, "no KEXT"):
                a.summarize([{"bad": True}])

    def test_strip_opaque_personality_values(self):
        r = a.summarize([{"id": "com.apple.driver.AppleANS2",
                          "io_kit_personalities": {"AppleANS": {
                              "IOClass": "AppleANS2",
                              "IOPropertyMatch": {"name": "ans",
                                                  "secret": "do-not-publish"}}}}])
        fields = r["matching_storage_graphics_RTKit_KEXTs"][0]["matching_personalities"][0]["selectors"]
        self.assertEqual(fields["IOPropertyMatch"], {"name": "ans"})
        self.assertNotIn("do-not-publish", str(fields))

    def test_afkresource_personality_is_kept_without_calling_it_registered(self):
        raw = [
            {"id": "com.apple.driver.Unrelated", "io_kit_personalities": {}},
            {"id": "com.apple.driver.AppleFirmwareKit", "io_kit_personalities": {
                "AFKResource": {"IOClass": "AFKResource",
                                "IOProviderClass": "IOResources"}}},
        ]
        result = a.summarize(raw)
        self.assertEqual(result["matched_KEXT_count"], 0)
        self.assertTrue(result["AFKResource_IOClass_declared_in_kernelcache_personalities"])
        self.assertFalse(result["AFKResource_metaclass_registered_in_guest"])
        found = result["AFK_and_firmware_kit_bundles"]
        self.assertEqual(found[0]["bundle_id"], "com.apple.driver.AppleFirmwareKit")
        self.assertFalse(found[0]["guest_start_observed"])
        self.assertEqual(found[0]["personalities"][0]["selectors"]["IOProviderClass"],
                         "IOResources")

    def test_documented_json_envelope_and_missing_metadata(self):
        result = a.summarize({"kexts": [{"id": "com.apple.driver.AppleDCP"}]})
        self.assertEqual(result["matched_KEXT_count"], 1)
        self.assertEqual(result["original_Apple_J490_ANS_identity"], {})


    def test_exact_apple_ans2_service_graph_uses_original_adt_selectors(self):
        rows = [
            {"id": "com.apple.driver.AppleA7IOP-ASCWrap-v6",
             "io_kit_personalities": {
                 "AppleASCWrapV6": {
                     "IOProviderClass": "AppleARMIODevice",
                     "IOClass": "AppleASCWrapV6",
                     "IONameMatch": ["iop,ascwrap-v6", "iop,ascwrap-v7"]}}},
            {"id": "com.apple.driver.RTBuddy",
             "io_kit_personalities": {
                 "RTBuddy": {
                     "IOProviderClass": "AppleA7IOPNub",
                     "IOClass": "RTBuddy",
                     "IONameMatch": "iop-nub,rtbuddy-v2"},
                 "RTBuddyService": {
                     "IOProviderClass": "RTBuddy",
                     "IOClass": "RTBuddyService"}}},
            {"id": "com.apple.iokit.IONVMeFamily",
             "io_kit_personalities": {
                 "AppleANS2NVMeController": {
                     "IOProviderClass": "RTBuddyService",
                     "IOClass": "AppleANS2NVMeController",
                     "IOPropertyMatch": {"role": "ANS2"}},
                 "AppleANS3NVMeController": {
                     "IOProviderClass": "RTBuddyService",
                     "IOClass": "AppleANS3NVMeController",
                     "IOPropertyMatch": {"role": "ANS2"}},
                 "AppleANS2CGv2Controller": {
                     "IOProviderClass": "RTBuddyService",
                     "IOClass": "AppleANS2CGv2Controller",
                     "IOPropertyMatch": {"role": "ANS2"}},
                 "AppleANS3CGv2Controller": {
                     "IOProviderClass": "RTBuddyService",
                     "IOClass": "AppleANS3CGv2Controller",
                     "IOPropertyMatch": {"role": "ANS2"}}}},
        ]
        adt = {
            "nodes": {
                "arm-io/ans": {
                    "present": True, "original_compatible": "iop,ascwrap-v6"},
                "arm-io/ans/iop-ans-nub": {
                    "present": True, "original_compatible": "iop-nub,rtbuddy-v2"},
            },
            "ANS_original_firmware_capabilities": {
                "role": {"present": True, "value": "ANS2"}},
        }
        result = a.summarize(rows, adt)
        graph = result["source_backed_IOKit_service_dependency_graph"]["ANS"]
        self.assertTrue(graph["all_required_matching_rules_found"])
        self.assertTrue(graph["controller_selection_is_ambiguous"])
        self.assertEqual(
            len(graph["stages"][-1]["kernelcache_personalities"]), 4)
        self.assertFalse(graph["guest_IORegistry_runtime_verification"])
        self.assertFalse(graph["storage_or_display_operational"])
        self.assertFalse(graph["stages"][0]["actual_matching_or_service_creation_observed"])

    def test_missing_adt_does_not_invent_a_matched_driver(self):
        rows = [{
            "id": "com.apple.iokit.IONVMeFamily",
            "io_kit_personalities": {"AppleANS2NVMeController": {
                "IOProviderClass": "RTBuddyService",
                "IOClass": "AppleANS2NVMeController",
                "IOPropertyMatch": {"role": "ANS2"}}},
        }]
        graph = a.summarize(rows)["source_backed_IOKit_service_dependency_graph"]["ANS"]
        self.assertFalse(graph["all_required_matching_rules_found"])
        self.assertEqual(graph["stages"][-1]["kernelcache_personalities"], [])
        self.assertIsNone(graph["firmware_role"])


if __name__ == "__main__":
    unittest.main()

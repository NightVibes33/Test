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

    def test_documented_json_envelope_and_missing_metadata(self):
        result = a.summarize({"kexts": [{"id": "com.apple.driver.AppleDCP"}]})
        self.assertEqual(result["matched_KEXT_count"], 1)
        self.assertEqual(result["original_Apple_J490_ANS_identity"], {})


if __name__ == "__main__":
    unittest.main()

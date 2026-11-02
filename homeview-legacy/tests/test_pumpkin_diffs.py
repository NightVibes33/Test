import importlib.util
import pathlib
import unittest

p=pathlib.Path(__file__).resolve().parents[1]/"scripts"/"scan_pumpkin_diffs.py"
spec=importlib.util.spec_from_file_location("scan_pumpkin_diffs",p)
mod=importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

class DiffTests(unittest.TestCase):
    def test_diff_symbol_and_key(self):
        data='+ _MobileGestalt_get_pumpkinMode\n+ "PumpkinMode"\n+ "WnCqFWpQgAFLfacM07K0RA"\n'
        rows=mod.extract("MobileGestalt",data)
        self.assertEqual(len(rows),3)
        self.assertFalse(any(x["runtime_verified"] for x in rows))
    def test_siri_logs_are_not_branch_proof(self):
        data='+ "originIsHomeAccessory: %{bool}d isPumpkin: %{bool}d"\n'
        rows=mod.extract("SiriAudioFlow",data)
        self.assertEqual(len(rows),1)
        self.assertIn("unproven",rows[0]["behavior_if_pumpkin_true"])
    def test_bounded_scan(self):
        result=mod.scan(lambda url:'+ "PumpkinMode"\n')
        self.assertEqual(result["source_count"],len(mod.SOURCES))
        self.assertFalse(result["errors"])
        self.assertIsNone(result["observed_guest_return"])

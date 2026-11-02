import importlib.util
import pathlib
import unittest

p=pathlib.Path(__file__).resolve().parents[1]/"scripts"/"observe_pumpkin_boot.py"
spec=importlib.util.spec_from_file_location("observe_pumpkin_boot",p)
module=importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class ObserverTests(unittest.TestCase):
    def test_no_logs_no_assumptions(self):
        data=module.inspect("Waiting for NAND service to publish\nunable to get framebuffer\n")
        self.assertIsNone(data["mg_pumpkinmode_returned"])
        self.assertIsNone(data["selected_homeview_shell"])
        self.assertFalse(data["mg_pumpkinmode_query_observed"])
    def test_genuine_query_and_value(self):
        data=module.inspect("MobileGestalt query PumpkinMode returned true\nlaunchd starting BreadBoard\n")
        self.assertTrue(data["mg_pumpkinmode_query_observed"])
        self.assertTrue(data["mg_pumpkinmode_returned"])
        self.assertEqual(data["selected_homeview_shell"],"BreadBoard")
        self.assertFalse(data["normal_homeview_ui_verified"])
    def test_host_hint_is_not_mg(self):
        data=module.inspect("HOST_PERSONALITY /chosen/PumpkinMode=1\n")
        self.assertFalse(data["mg_pumpkinmode_query_observed"])
        self.assertIsNone(data["mg_pumpkinmode_returned"])

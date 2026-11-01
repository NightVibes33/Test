import importlib.util
import pathlib
import unittest

target = pathlib.Path(__file__).resolve().parents[1] / "scripts" / "firmware_probe.py"
spec = importlib.util.spec_from_file_location("firmware_probe", target)
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)


class FirmwareProbeTests(unittest.TestCase):
    catalog = 'productType: "HomeAccessory17,1", version: "27.2", build: "24V514", url: "https://test.invalid/update.aea"'
    bringup = "HomeAccessory17,1 actual native BreadBoard dashboard"

    def test_expected_upstream(self):
        result = probe.inspect(self.catalog, self.bringup)
        self.assertTrue(result["firmware_catalog_present"])
        self.assertFalse(result["intel_homeview_boot_verified"])
        self.assertFalse(result["firmware_downloaded"])

    def test_reject_other_build(self):
        with self.assertRaises(ValueError):
            probe.inspect(self.catalog.replace("24V514", "broken"), self.bringup)

    def test_reject_missing_breadboard(self):
        with self.assertRaises(ValueError):
            probe.inspect(self.catalog, "No native shell evidence")


if __name__ == "__main__":
    unittest.main()

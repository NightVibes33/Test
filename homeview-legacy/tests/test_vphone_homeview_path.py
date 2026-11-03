import importlib.util
from pathlib import Path
import unittest

PATH = Path(__file__).resolve().parents[1] / "scripts" / "vphone_homeview_path.py"
spec = importlib.util.spec_from_file_location("vphone_homeview_path", PATH)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


class VPhonePathTests(unittest.TestCase):
    def test_macos_27_cannot_compile_the_paravirtual_display(self):
        report = mod.plan(27, False)
        self.assertIn("lakr233/vphone-cli", report["credit"])
        self.assertEqual(report["boot_kernel"]["kernel"], "kernelcache.research.vphone600")
        self.assertEqual(report["restore_base"]["build"], "23L773")
        self.assertFalse(report["display"]["qemu_can_present_pv_framebuffer"])
        self.assertFalse(report["j490_hardware_kernel_is_the_display_path"])
        self.assertFalse(report["breadboard_boot_proven"])
        self.assertIn("ForceNoBuddy", report["setup_bypass"])

    def test_older_host_with_pvg_is_the_only_qemu_display_case(self):
        self.assertTrue(mod.plan(26, True)["display"]["qemu_can_present_pv_framebuffer"])
        self.assertFalse(mod.plan(26, False)["display"]["qemu_can_present_pv_framebuffer"])
        self.assertFalse(mod.plan(27, True)["display"]["qemu_can_present_pv_framebuffer"])


if __name__ == "__main__":
    unittest.main()

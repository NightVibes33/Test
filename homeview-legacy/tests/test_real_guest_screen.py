import importlib.util
import pathlib
import tempfile
import unittest

target=pathlib.Path(__file__).resolve().parents[1]/"scripts"/"capture_real_guest_screen.py"
spec=importlib.util.spec_from_file_location("capture_real_guest_screen",target)
mod=importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

class CaptureTests(unittest.TestCase):
    def test_missing_monitor_not_a_screenshot(self):
        with tempfile.TemporaryDirectory() as t:
            result=mod.capture(pathlib.Path(t)/"missing.sock",pathlib.Path(t)/"out.ppm")
        self.assertFalse(result["guest_framebuffer_captured"])
        self.assertFalse(result["apple_setup_or_breadboard_verified"])
    def test_does_not_create_fake_png(self):
        with tempfile.TemporaryDirectory() as t:
            dest=pathlib.Path(t)/"out.ppm"
            mod.capture(pathlib.Path(t)/"missing.sock",dest)
            self.assertFalse(dest.exists())

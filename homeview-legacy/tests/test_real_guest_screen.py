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

    def test_existing_screendump_is_kept_and_not_called_apple(self):
        with tempfile.TemporaryDirectory() as t:
            dest = pathlib.Path(t) / "frame.ppm"
            width, height = 64, 64
            header = f"P6\n{width} {height}\n255\n".encode()
            dest.write_bytes(header + bytes([1, 2, 3]) * (width * height))
            result = mod.capture(pathlib.Path(t) / "missing.sock", dest)
            png = dest.with_suffix(".png")
            self.assertTrue(result["qemu_monitor_surface_captured"])
            self.assertFalse(result["guest_framebuffer_captured"])
            self.assertFalse(result["apple_setup_or_breadboard_verified"])
            self.assertFalse(result["surface_is_apple_display_service"])
            self.assertTrue(png.is_file())
            self.assertGreater(png.stat().st_size, 32)

import importlib.util
from pathlib import Path
import unittest

PATH = Path(__file__).resolve().parents[1] / "scripts" / "probe_vresearch_machine.py"
spec = importlib.util.spec_from_file_location("probe_vresearch_machine", PATH)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


class VResearchMachineTests(unittest.TestCase):
    def test_command_is_the_apple_virtio_root_machine_without_a_framebuffer(self):
        argv = mod.qemu_argv(
            "qemu-system-aarch64", "OpenAVB.bin", "OpenSEP.bin",
            "aux.img", "root.img", "serial.log", "qemu.log", "mon.sock")
        text = " ".join(argv)
        self.assertIn("vresearch101", text)
        self.assertIn("gfx-device=none", text)
        self.assertIn("id=root-pci", text)
        self.assertIn("id=aux-pci", text)
        self.assertIn("-bios", argv)
        self.assertNotIn("-bootkc", argv)
        self.assertNotIn("darwin", argv)

    def test_serial_text_is_not_a_breadboard_frame(self):
        report = mod.interpret(
            "BreadBoard SpringBoard", "", None, 20.0,
            "screendump: No console available")
        self.assertFalse(report["breadboard_boot_proven"])
        self.assertFalse(report["guest_framebuffer_captured"])
        self.assertFalse(report["attached_disk_is_homeview_root"])
        self.assertFalse(report["linear_bootloader_framebuffer"])
        self.assertTrue(report["machine_stayed_up"])
        self.assertEqual(report["gfx_device"], "none")


if __name__ == "__main__":
    unittest.main()

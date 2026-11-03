import importlib.util
from pathlib import Path
import unittest

PATH = Path(__file__).resolve().parents[1] / "scripts" / "inventory_restore_ramdisk.py"
spec = importlib.util.spec_from_file_location("inventory_restore_ramdisk", PATH)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


class RestoreRamdiskInventoryTests(unittest.TestCase):
    def test_names_are_not_a_running_springboard(self):
        text = "\n".join((
            "MOUNT_OK",
            "System/Library/CoreServices/SpringBoard.app/SpringBoard",
            "usr/standalone/update/ramdisk/AppleFirmwareKit.kext",
        ))
        result = mod.classify(text, True)
        self.assertTrue(result["SpringBoard_present_on_restore_ramdisk"])
        self.assertTrue(result["AppleFirmwareKit_present_on_restore_ramdisk"])
        self.assertFalse(result["BreadBoard_present_on_restore_ramdisk"])
        self.assertFalse(result["SpringBoard_boot_proven"])
        self.assertFalse(result["restore_ramdisk_is_installed_HomeView_system"])

    def test_failed_mount_does_not_claim_absence(self):
        result = mod.classify("MOUNT_FAILED\n", False)
        self.assertFalse(result["mount_succeeded"])
        self.assertFalse(result["SpringBoard_present_on_restore_ramdisk"])
        self.assertFalse(result["SpringBoard_boot_proven"])


if __name__ == "__main__":
    unittest.main()

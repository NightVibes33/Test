import importlib.util
from pathlib import Path
import unittest

PATH = Path(__file__).resolve().parents[1] / "scripts" / "summarize_ota_payload_index.py"
spec = importlib.util.spec_from_file_location("summarize_ota_payload_index", PATH)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


class PayloadIndexTests(unittest.TestCase):
    def test_small_springboard_set_can_use_the_ramdisk_slot(self):
        text = "\n".join((
            "-rwxr-xr-x 2026-10-13T00:00:00Z 2 MB System/Library/CoreServices/SpringBoard.app/SpringBoard",
            "-rwxr-xr-x 2026-10-13T00:00:00Z 1 MB sbin/launchd",
            "-rwxr-xr-x 2026-10-13T00:00:00Z 3 MB usr/lib/dyld",
            "-rw-r--r-- 2026-10-13T00:00:00Z 42 kB AssetData/boot/Firmware/141-21962-183.dmg.trustcache",
            "-rw-r--r-- 2026-10-13T00:00:00Z 8 kB Firmware/system.trustcache",
            "-rw-r--r-- 2026-10-13T00:00:00Z 4 kB Firmware/arm64eSURamDisk.dmg.trustcache",
        ))
        result = mod.summarize(text)
        self.assertTrue(result["springboard_listed"])
        self.assertTrue(result["fits_qemu_ramdisk_slot"])
        self.assertIn("Firmware/system.trustcache", result["system_trustcache_paths"])
        self.assertFalse(result["springboard_boot_proven"])
        self.assertFalse(result["volume_built"])
        self.assertFalse(result["qemu_has_nand_block_device"])
        self.assertTrue(any(path.endswith("141-21962-183.dmg") for path in result["candidate_system_dmgs"]))
        self.assertFalse(any("arm64eSURamDisk" in path for path in result["candidate_system_dmgs"]))

    def test_oversized_dyld_cache_does_not_fit_the_ramdisk_slot(self):
        text = "\n".join((
            "-rwxr-xr-x 2026-10-13T00:00:00Z 2 MB System/Library/CoreServices/SpringBoard.app/SpringBoard",
            "-rwxr-xr-x 2026-10-13T00:00:00Z 9 GB System/Library/Caches/com.apple.dyld/dyld_shared_cache_arm64e",
        ))
        result = mod.summarize(text)
        self.assertTrue(result["springboard_listed"])
        self.assertFalse(result["fits_qemu_ramdisk_slot"])
        self.assertGreater(result["listed_boot_bytes"], result["guest_ramdisk_limit_bytes"])


if __name__ == "__main__":
    unittest.main()

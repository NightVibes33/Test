import importlib.util
from pathlib import Path
import unittest

PATH = Path(__file__).resolve().parents[1] / "scripts" / "assess_qemu_disk.py"
spec = importlib.util.spec_from_file_location("assess_qemu_disk", PATH)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


class QemuDiskTests(unittest.TestCase):
    def test_ramdisk_machine_has_no_block_backend(self):
        report = mod.assess("info->ramdisk_f = check_and_open(info->ramdisk, \"error opening ramdisk\");\n")
        self.assertTrue(report["ramdisk_path_present"])
        self.assertFalse(report["qemu_creates_guest_disk"])
        self.assertFalse(report["apple_kernel_will_mount_that_disk_proven"])

    def test_virtio_source_is_reported_without_claiming_xnu_mounts_it(self):
        report = mod.assess("virtio-blk-device and a ramdisk\n")
        self.assertTrue(report["virtio_blk_present"])
        self.assertTrue(report["qemu_creates_guest_disk"])
        self.assertFalse(report["apple_kernel_will_mount_that_disk_proven"])


if __name__ == "__main__":
    unittest.main()

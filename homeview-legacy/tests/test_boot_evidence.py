import importlib.util
import pathlib
import unittest

target=pathlib.Path(__file__).resolve().parents[1]/"scripts"/"boot_evidence.py"
spec=importlib.util.spec_from_file_location("boot_evidence",target)
module=importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class ClassifierTests(unittest.TestCase):
    def test_empty(self):
        data=module.classify("")
        self.assertEqual(data["stage"],"no_serial_output")
        self.assertFalse(data["apple_restore_userspace_started"])
        self.assertFalse(data["native_breadboard_display_verified"])

    def test_xnu_panic_not_userspace(self):
        text=("iBoot version: qemu-sptm\nDarwin Image4 Extension Version 7.0\n"
              "BSD root: md0\napfs_vfsop_mountroot:\n"
              "panic(cpu 0 caller 0x123): PC alignment exception\n")
        data=module.classify(text)
        self.assertEqual(data["stage"],"apfs_ramdisk")
        self.assertIsNotNone(data["first_kernel_panic"])
        self.assertFalse(data["apple_launchd_pid1_started"])

    def test_real_restore_launchd_is_not_homeview(self):
        text=("iBoot version: qemu-sptm\nDarwin Image4 Extension Version 7.0\n"
              "BSD root: md0\napfs_vfsop_mountroot:\n"
              "com.apple.xpc.launchd|1970 <Notice>: Darwin Bootstrapper Version 7.0.0\n"
              "com.apple.xpc.launchd|1970 <Notice>: Restore environment starting.\n"
              "com.apple.xpc.launchd|1970 <Notice>: launchd logging initialized. name: com.apple.xpc.launchd pid: 1\n"
              "patchd: updating\nramrod_display_set_granular_progress_forced: 13.896354\n"
              "Waiting for NAND service to publish\nunable to get framebuffer\n"
              "patchd: giving up trying to create framebuffer\n")
        data=module.classify(text)
        self.assertEqual(data["stage"],"apple_restore_userspace")
        self.assertTrue(data["apple_launchd_pid1_started"])
        self.assertTrue(data["apple_restore_patchd_seen"])
        self.assertEqual(data["nand_service_wait_count"],1)
        self.assertEqual(data["framebuffer_missing_count"],1)
        self.assertEqual(data["restore_progress_max_percent"],13.896354)
        self.assertFalse(data["normal_homeview_os_booted"])
        self.assertFalse(data["native_apple_hello_display_verified"])

    def test_fake_launchd_word_not_enough(self):
        data=module.classify("launchd maybe started but no pid or Apple provenance")
        self.assertFalse(data["apple_launchd_pid1_started"])
        self.assertFalse(data["normal_homeview_os_booted"])

import importlib.util
from pathlib import Path
import unittest

FILE = Path(__file__).resolve().parents[1] / "scripts" / "assess_ans_port_gap.py"
SPEC = importlib.util.spec_from_file_location("assess_ans_port_gap", FILE)
mod = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(mod)

ANS = """#define NVME_APPLE_VENDOR_REG_SIZE (0x60000)
AppleRTKitOps apple_rtkit_new( apple_ans_start(
pci_new(-1, TYPE_NVME) is-apple-ans apple_ans_set_irq
sysbus_init_mmio(sbd reg[1] reg[3] reg[5] reg[7]
NVME_APPLE_BOOT_STATUS_OK "pre-loaded"
"""
SART = "memory_region_init_iommu apple_sart_translate"


def fixture():
    return {"device":"HomeAccessory17,1","source":"Apple J490 original",
            "nodes":{
                "arm-io/ans":{
                    "present":True,"original_compatible":"iop,ascwrap-v6",
                    "reg_windows":[{"length":hex(x)} for x in
                        (0x88000,0x4000,0,0x60000,0x1000000,0xc000)]},
                "arm-io/sart-ans":{
                    "present":True,"original_compatible":"sart,coastguard"}}}


class PortGapTests(unittest.TestCase):
    def test_vendor_window_matches_without_claiming_compatible_abi(self):
        got = mod.assess(fixture(), ANS, SART)
        self.assertTrue(got["vendor_window_length_matches_upstream"])
        self.assertTrue(got["upstream_rtkit_hooks_present"])
        self.assertTrue(got["upstream_nvme_device_construction_present"])
        self.assertTrue(got["upstream_sart_iommu_mapping_present"])
        self.assertIn(2, got["original_ans_zero_length_reg_indices"])
        self.assertFalse(got["j490_rtkit_abi_verified"])
        self.assertFalse(got["safe_direct_port_verified"])
        self.assertTrue(got["blocking_differences"])

    def test_changed_upstream_layout_cannot_be_declared_compatible(self):
        x = fixture()
        x["nodes"]["arm-io/ans"]["reg_windows"][3]["length"] = "0x4000"
        got = mod.assess(x, ANS, "")
        self.assertFalse(got["vendor_window_length_matches_upstream"])
        self.assertFalse(got["upstream_sart_iommu_mapping_present"])
        self.assertFalse(got["native_homeview_boot_verified"])

    def test_wrong_contract_type_rejected(self):
        with self.assertRaises(ValueError):
            mod.assess([], ANS, SART)


if __name__ == "__main__":
    unittest.main()

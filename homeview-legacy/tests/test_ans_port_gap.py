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
BOARD = "ans = apple_ans_from_node(child, APPLE_A7IOP_V4, sec_bus);"



def fixture():
    return {"device":"HomeAccessory17,1","source":"Apple J490 original",
            "nodes":{
                "arm-io/ans":{
                    "present":True,"original_compatible":"iop,ascwrap-v6",
                    "reg_windows":[
                        {"length":hex(n),"guest_physical_base":hex(base)}
                        for base,n in (
                            (0x389600000,0x88000),
                            (0x389050000,0x4000),
                            (0x210000000,0),
                            (0x38dcc0000,0x60000),
                            (0x38b000000,0x1000000),
                            (0x38db90000,0xc000),
                            (0x38dd47c00,0x4000),
                        )]},
                "arm-io/sart-ans":{
                    "present":True,"original_compatible":"sart,coastguard",
                    "reg_windows":[
                        {"length":"0xc000","guest_physical_base":"0x38dc50000"},
                        {"length":"0x4000","guest_physical_base":"0x38dd44000"},
                        {"length":"0x4000","guest_physical_base":"0x38dcc0000"},
                    ]}}}


class PortGapTests(unittest.TestCase):
    def test_vendor_window_matches_without_claiming_compatible_abi(self):
        got = mod.assess(fixture(), ANS, SART, BOARD)
        self.assertTrue(got["vendor_window_length_matches_upstream"])
        self.assertTrue(got["upstream_rtkit_hooks_present"])
        self.assertTrue(got["upstream_nvme_device_construction_present"])
        self.assertTrue(got["upstream_sart_iommu_mapping_present"])
        self.assertIn(2, got["original_ans_zero_length_reg_indices"])
        self.assertFalse(got["j490_rtkit_abi_verified"])
        self.assertFalse(got["safe_direct_port_verified"])
        self.assertTrue(got["blocking_differences"])
        self.assertTrue(got["upstream_board_uses_a7iop_v4"])
        self.assertTrue(got["j490_ascwrap_v6_vs_upstream_v4_abi_incompatible_until_verified"])
        self.assertEqual(got["shared_ans_sart_physical_window_count"], 2)
        self.assertEqual(
            [(p["ans_reg_index"], p["sart_reg_index"], p["length_bytes"])
             for p in got["shared_ans_sart_physical_window_ranges"]],
            [(3, 2, 0x4000), (6, 1, 0x400)])
        self.assertTrue(got["j490_sart_vendor_window_overlap"])
        self.assertFalse(got["safe_independent_mmio_mapping_verified"])

    def test_changed_upstream_layout_cannot_be_declared_compatible(self):
        x = fixture()
        x["nodes"]["arm-io/ans"]["reg_windows"][3]["length"] = "0x4000"
        got = mod.assess(x, ANS, "")
        self.assertFalse(got["vendor_window_length_matches_upstream"])
        self.assertFalse(got["upstream_sart_iommu_mapping_present"])
        self.assertFalse(got["native_homeview_boot_verified"])

    def test_zero_length_holes_and_disjoint_ranges_not_mapped(self):
        contract = fixture()
        contract["nodes"]["arm-io/sart-ans"]["reg_windows"] = [
            {"length": "0x4000", "guest_physical_base": "0x500000000"},
            {"length": "0", "guest_physical_base": "0x38dcc0000"},
        ]
        got = mod.assess(contract, ANS, SART, BOARD)
        self.assertEqual(got["shared_ans_sart_physical_window_count"], 0)
        self.assertTrue(got["safe_independent_mmio_mapping_verified"])

    def test_bad_physical_range_rejected(self):
        contract = fixture()
        contract["nodes"]["arm-io/ans"]["reg_windows"][3]["guest_physical_base"] = "-1"
        with self.assertRaisesRegex(ValueError, "physical range"):
            mod.assess(contract, ANS, SART, BOARD)

    def test_wrong_contract_type_rejected(self):
        with self.assertRaises(ValueError):
            mod.assess([], ANS, SART)


if __name__ == "__main__":
    unittest.main()

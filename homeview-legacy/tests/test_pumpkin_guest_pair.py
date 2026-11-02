import importlib.util
import pathlib
import unittest

p = pathlib.Path(__file__).resolve().parents[1] / "scripts" / "compare_pumpkin_guest_pair.py"
spec = importlib.util.spec_from_file_location("compare_pumpkin_guest_pair", p)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

C = module.CONTROL
P = module.PUMPKIN
VERIFIED = {"exactly_one_property_added": True,
            "all_other_nodes_and_properties_identical": True,
            "property": "/chosen/PumpkinMode"}


def evidence(values=None):
    boot = {"attempts": [
        {"variant": C, "stage": "apple_restore_userspace",
         "nand_service_wait_count": 10, "framebuffer_missing_count": 3},
        {"variant": P, "stage": "apple_restore_userspace",
         "nand_service_wait_count": 12, "framebuffer_missing_count": 3},
    ]}
    logs = {}
    for name in (C, P):
        value = values.get(name) if values else None
        logs["native-homeview-" + name + "-serial.log"] = {
            "mg_pumpkinmode_query_observed": value is not None,
            "mg_pumpkinmode_returned": value,
            "mg_pumpkinmode_return_evidence": value is not None}
    return boot, {"results": logs}


class GuestPairTests(unittest.TestCase):
    def test_realistic_restore_stall_not_getter_proof(self):
        b, o = evidence()
        r = module.compare(b, o, VERIFIED)
        self.assertTrue(r["paired_boot_observed"])
        self.assertEqual(r["nand_wait_delta_experimental_minus_control"], 2)
        self.assertIsNone(r["MG_return_changed"])
        self.assertFalse(r["Apple_MobileGestalt_getter_source_proven"])

    def test_distinct_guest_MG_values_are_logged_but_not_derivation(self):
        b, o = evidence({C: False, P: True})
        r = module.compare(b, o, VERIFIED)
        self.assertTrue(r["MG_return_changed"])
        self.assertEqual(r["result"], "MG_value_difference_logged_backing_source_unproven")
        self.assertFalse(r["Apple_MobileGestalt_getter_source_proven"])

    def test_missing_pair_is_unverified(self):
        b, o = evidence()
        b["attempts"] = []
        self.assertEqual(module.compare(b, o, VERIFIED)["result"],
                         "not_evaluable_missing_guest_evidence")

    def test_unverified_adt_pair_rejected(self):
        b, o = evidence()
        self.assertEqual(module.compare(b, o, {})["result"],
                         "not_evaluable_no_verified_ADT_pair")

    def test_mmio_registers_bounded_and_not_functional(self):
        log = ("HOMEVIEW_MMIO_TRACE installed arm-io/ans base=0x100 length=0x4000\n"
               "HOMEVIEW_MMIO_TRACE read arm-io/ans off=0x20 size=4\n"
               "HOMEVIEW_MMIO_TRACE write arm-io/ans off=0x24 value=0xff size=4\n")
        r = module.mmio_summary(log)
        self.assertEqual(r["accesses_observed"], 2)
        self.assertEqual(r["devices"]["arm-io/ans"]["writes"], 1)
        self.assertFalse(r["real_hardware_functionality_verified"])


if __name__ == "__main__":
    unittest.main()

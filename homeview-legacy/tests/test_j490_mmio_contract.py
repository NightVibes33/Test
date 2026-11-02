import importlib.util
import pathlib
import struct
import unittest

root = pathlib.Path(__file__).resolve().parents[1] / "scripts"
def load(name):
    path = root / (name + ".py")
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod

extract = load("extract_j490_mmio_contract")
verify = load("verify_j490_mmio_log")


class Node:
    def __init__(self, name, props=None, children=()):
        self.props = {"name": name, **(props or {})}
        self.children = list(children)


def fake_raw_tree():
    def reg(offset, length):
        return struct.pack("<QQ", offset, length)
    def child(name, off, length, compat):
        return Node(name, {"reg": reg(off, length),
                           "compatible": compat,
                           "interrupts": struct.pack("<II", 20, 21)})
    return Node("device-tree", children=[
        Node("arm-io", {"ranges": struct.pack("<QQQ", 0, 0x380000000, 0x4000000)},
             [child("ans", 0x9600000, 0x8000, b"iop,ascwrap-v6\x00"),
              child("sart-ans", 0x9800000, 0x2000, b"sart,coastguard\x00"),
              child("dcp", 0x92e00000, 0x4000, b"iop,ascwrap-v6\x00")])
    ])


class MMIOContractTests(unittest.TestCase):
    def test_original_ans_nvme_personality_properties(self):
        tree = fake_raw_tree()
        ans = tree.children[0].children[0]
        ans.props.update({
            "nvme-linear-sq": "u32:1",
            "nvme-num-sl": struct.pack("<I", 2),
            "nvme-queue-entries": struct.pack("<Q", 64),
            "nvme-secure-bar": b"\x00\xff\x01\x02\x03\x04\x05\x06\x07",
            "namespaces": b"",
        })
        data = extract.collect(tree)
        caps = data["ANS_original_firmware_capabilities"]
        self.assertEqual(caps["nvme-linear-sq"]["unsigned"], 1)
        self.assertEqual(caps["nvme-num-sl"]["kind"], "raw-u32")
        self.assertEqual(caps["nvme-queue-entries"]["unsigned"], 64)
        self.assertEqual(caps["nvme-secure-bar"]["length"], 9)
        self.assertEqual(caps["namespaces"]["length"], 0)
        self.assertFalse(caps["nvme-interrupt-idx"]["present"])
        self.assertFalse(data["controller_emulation_implemented"])

    def test_integer_property_rejects_malformed_values(self):
        for raw in ("u32:garbage", "u32:-1", "u32:0x100000000"):
            with self.assertRaises(ValueError):
                extract.describe_original_adt_property({"nvme-linear-sq": raw},
                                                       "nvme-linear-sq")

    def test_expected_physical_addresses_and_irqs(self):
        data = extract.collect(fake_raw_tree())
        self.assertEqual(data["nodes"]["arm-io/ans"]["reg_windows"][0]
                         ["guest_physical_base"], hex(0x380000000 + 0x9600000))
        self.assertEqual(data["nodes"]["arm-io/ans"]["interrupts_raw"], [20, 21])
        self.assertFalse(data["controller_emulation_implemented"])

    def test_install_addresses_must_match_apple_source(self):
        data = extract.collect(fake_raw_tree())
        expected = int(data["nodes"]["arm-io/ans"]["reg_windows"][0]
                       ["guest_physical_base"], 0)
        log = f"HOMEVIEW_MMIO_TRACE installed arm-io/ans base=0x{expected:x} length=0x4000\n"
        checked = verify.check(data, log)
        self.assertEqual(checked["registered_region_count"], 1)
        with self.assertRaisesRegex(ValueError, "disagrees"):
            verify.check(data, log.replace(hex(expected), "0x10000"))

    def test_multiregion_apple_ans_indices(self):
        data = extract.collect(fake_raw_tree())
        a = data["nodes"]["arm-io/ans"]
        a["reg_windows"].append({
            "relative_offset": "0x8000",
            "guest_physical_base": hex(int(data["arm_io_phys_base"], 0) + 0x8000),
            "length": "0x8000",
        })
        window = a["reg_windows"][1]
        base = window["guest_physical_base"]
        log = f"HOMEVIEW_MMIO_TRACE installed arm-io/ans base={base} length=0x4000 index=1\\n"
        observed = verify.check(data, log)
        self.assertEqual(observed["registered_regions"][0]["window_index"], 1)
        with self.assertRaisesRegex(ValueError, "disagrees"):
            verify.check(data, log.replace("index=1", "index=0"))
        with self.assertRaisesRegex(ValueError, "unregistered"):
            verify.check(data, "HOMEVIEW_MMIO_TRACE read arm-io/ans off=0x20 size=4 index=1\\n")

    def test_overlap_skip_requires_a_real_registered_overlap(self):
        data = extract.collect(fake_raw_tree())
        base = data["nodes"]["arm-io/ans"]["reg_windows"][0]["guest_physical_base"]
        registered = f"HOMEVIEW_MMIO_TRACE installed arm-io/ans base={base} length=0x4000 index=0\\n"
        skip = f"HOMEVIEW_MMIO_TRACE skipped_overlap arm-io/ans base={base} length=0x4000 index=0\\n"
        self.assertEqual(len(verify.check(data, registered + skip)["skipped_overlap_windows"]), 1)
        with self.assertRaisesRegex(ValueError, "not demonstrated"):
            verify.check(data, skip)

    def test_full_apple_ans_mmio_window_and_nvmmu_offsets(self):
        data = extract.collect(fake_raw_tree())
        win = data["nodes"]["arm-io/ans"]["reg_windows"][0]
        win["length"] = "0x88000"
        base = win["guest_physical_base"]
        log = (
            f"HOMEVIEW_MMIO_TRACE installed arm-io/ans base={base} length=0x88000 index=0\\n"
            "HOMEVIEW_MMIO_TRACE read arm-io/ans off=0x28100 size=4 index=0\\n"
        )
        result = verify.check(data, log)
        self.assertTrue(result["full_primary_ANS_window_installed"])
        self.assertEqual(result["access_sample"][0]["linux_register_reference"],
                         "ans_nvmmu_num_tcbs")
        self.assertIn("ans_linear_sq_control",
                      result["registered_regions"][0]["linux_ANS_reference_offsets_in_range"])
        with self.assertRaisesRegex(ValueError, "disagrees"):
            verify.check(data, log.replace("length=0x88000", "length=0x88001"))
        # The old 16KiB tracing limit cannot observe this offset.
        old = f"HOMEVIEW_MMIO_TRACE installed arm-io/ans base={base} length=0x4000 index=0\\n"
        with self.assertRaisesRegex(ValueError, "exceeds"):
            verify.check(data, old + "HOMEVIEW_MMIO_TRACE read arm-io/ans off=0x28100 size=4 index=0\\n")

    def test_unregistered_access_is_rejected(self):
        data = extract.collect(fake_raw_tree())
        with self.assertRaisesRegex(ValueError, "unregistered"):
            verify.check(data, "HOMEVIEW_MMIO_TRACE read arm-io/ans off=0x20 size=4\n")

    def test_child_spi_register_not_translated_to_arm_mmio(self):
        root = fake_raw_tree()
        arm = root.children[0]
        arm.children.append(Node("spi1", {"reg": struct.pack("<QQ", 0x8000, 0x1000)}, [
            Node("multi-touch", {"reg": "u32:0x1"})]))
        r = extract.collect(root)
        self.assertEqual(r["nodes"]["arm-io/spi1/multi-touch"]["reg_windows"], [])
        self.assertTrue(r["nodes"]["arm-io/spi1/multi-touch"]
                        ["parent_bus_register_not_MMIO"])

    def test_bad_range_or_reg_is_rejected(self):
        root = fake_raw_tree()
        root.children[0].props["ranges"] = struct.pack("<QQQ", 1, 2, 3)
        with self.assertRaisesRegex(ValueError, "Unsupported"):
            extract.collect(root)
        root = fake_raw_tree()
        root.children[0].children[0].props["reg"] = b"\x00"
        with self.assertRaisesRegex(ValueError, "Unsupported"):
            extract.collect(root)


if __name__ == "__main__":
    unittest.main()

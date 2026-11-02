import importlib.util
import pathlib
import unittest

p = pathlib.Path(__file__).resolve().parents[1] / "scripts" / "verify_pumpkin_adt_pair.py"
spec = importlib.util.spec_from_file_location("verify_pumpkin_adt_pair", p)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class Node:
    def __init__(self, name, props=None, children=()):
        self.props = {"name": name, **(props or {})}
        self.children = list(children)


def pair():
    control = Node("device-tree", {"model": "J490AP"}, [
        Node("chosen", {"firmware-version": "qemu-sptm"}),
        Node("arm-io", children=[Node("ans"), Node("dcp")])])
    experiment = Node("device-tree", {"model": "J490AP"}, [
        Node("chosen", {"firmware-version": "qemu-sptm", "PumpkinMode": "u32:0x1"}),
        Node("arm-io", children=[Node("ans"), Node("dcp")])])
    return control, experiment


class PairTests(unittest.TestCase):
    def test_exact_one_property_passes(self):
        result = module.compare_nodes(*pair())
        self.assertTrue(result["all_other_nodes_and_properties_identical"])
        self.assertFalse(result["mobilegestalt_reads_property_verified"])

    def test_dock_change_rejected(self):
        a, b = pair()
        b.children.append(Node("dock-connect"))
        with self.assertRaisesRegex(ValueError, "topology"):
            module.compare_nodes(a, b)

    def test_product_type_change_rejected(self):
        a, b = pair()
        b.props["model"] = "iPhone"
        with self.assertRaisesRegex(ValueError, "Other Apple ADT"):
            module.compare_nodes(a, b)

    def test_extra_change_rejected(self):
        a, b = pair()
        b.children[0].props["foo"] = "bar"
        with self.assertRaisesRegex(ValueError, "Other Apple ADT"):
            module.compare_nodes(a, b)

    def test_absent_or_zero_probe_rejected(self):
        a, b = pair()
        b.children[0].props["PumpkinMode"] = "u32:0"
        with self.assertRaisesRegex(ValueError, "PumpkinMode=1"):
            module.compare_nodes(a, b)
        del b.children[0].props["PumpkinMode"]
        with self.assertRaisesRegex(ValueError, "missing PumpkinMode"):
            module.compare_nodes(a, b)

    def test_duplicate_child_rejected(self):
        a, b = pair()
        b.children.append(Node("chosen"))
        with self.assertRaisesRegex(ValueError, "Duplicate"):
            module.compare_nodes(a, b)


if __name__ == "__main__":
    unittest.main()

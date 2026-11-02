import importlib.util
import pathlib
import unittest

p = pathlib.Path(__file__).resolve().parents[1] / "scripts" / "verify_ans_adt_probe.py"
spec = importlib.util.spec_from_file_location("verify_ans_adt_probe", p)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


class Node:
    def __init__(self, name, props=None, children=()):
        self.props = {"name": name, **(props or {})}
        self.children = list(children)


def tree(restored):
    def node(name, value, children=()):
        return Node(name, {"compatible": value} if value is not None else {}, children)
    original = b"apple,real-ans\0"
    return Node("device-tree", children=[
        Node("chosen"),
        Node("arm-io", children=[
            node("ans", original if restored else None,
                 [node("iop-ans-nub", "apple,iop-nub" if restored else None)]),
            node("sart-ans", "apple,sart" if restored else None),
        ]),
    ])


class ANSTests(unittest.TestCase):
    def test_preserves_only_original_apple_compatible(self):
        r = mod.verify_nodes(tree(False), tree(True), tree(True))
        self.assertTrue(r["all_other_ADT_fields_unchanged"])
        self.assertEqual(len(r["changed_properties"]), 3)
        self.assertFalse(r["true_ANS_or_NAND_device_implemented"])

    def test_refuse_invented_compatible(self):
        c, p, raw = tree(False), tree(True), tree(True)
        p.children[1].children[0].props["compatible"] = b"fake,driver"
        with self.assertRaisesRegex(ValueError, "exact Apple"):
            mod.verify_nodes(c, p, raw)

    def test_refuse_non_compatible_changes(self):
        c, p, raw = tree(False), tree(True), tree(True)
        p.children[1].props["platform-name"] = "wrong"
        with self.assertRaisesRegex(ValueError, "non-allowlisted"):
            mod.verify_nodes(c, p, raw)

    def test_refuse_topology_change(self):
        c, p, raw = tree(False), tree(True), tree(True)
        p.children.append(Node("extra"))
        with self.assertRaisesRegex(ValueError, "topology"):
            mod.verify_nodes(c, p, raw)


if __name__ == "__main__":
    unittest.main()

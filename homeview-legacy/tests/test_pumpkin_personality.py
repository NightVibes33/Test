import importlib.util
import pathlib
import unittest

p=pathlib.Path(__file__).resolve().parents[1]/"scripts"/"pumpkin_personality.py"
spec=importlib.util.spec_from_file_location("pumpkin_personality",p)
module=importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class Node:
    def __init__(self,name,children=()):
        self.props={"name":name}
        self.children=list(children)

def tree():
    return Node("root",[Node("chosen"), Node("arm-io",[
        Node("ans"),Node("dcp"),Node("sgx"),
    ])])

class PersonalityTests(unittest.TestCase):
    def test_profile_grounded_identity(self):
        profile=module.load_profile()
        self.assertEqual(profile["identity"]["product_type"],"HomeAccessory17,1")
        self.assertIsNone(profile["identity"]["hardware_model"])
        self.assertIsNone(profile["gestalt"]["observed_guest_value"])
        self.assertEqual(profile["nvram"]["inject_keys"],{})
    def test_default_never_spoofs_gestalt(self):
        root=tree()
        result=module.apply(root,module.load_profile())
        self.assertFalse(result["pumpkin_probe_injected"])
        self.assertNotIn("PumpkinMode",root.children[0].props)
        self.assertIsNone(result["mobilegestalt_pumpkinmode_returned_value"])
    def test_explicit_adt_experiment_only(self):
        root=tree()
        result=module.apply(root,module.load_profile(),True)
        self.assertTrue(result["pumpkin_probe_injected"])
        self.assertEqual(root.children[0].props["PumpkinMode"],"u32:1")
        self.assertIsNone(result["mobilegestalt_pumpkinmode_returned_value"])
        with self.assertRaises(ValueError):
            module.apply(root,module.load_profile(),True)
    def test_missing_chosen_rejected(self):
        with self.assertRaises(ValueError):
            module.apply(Node("root"),module.load_profile(),True)

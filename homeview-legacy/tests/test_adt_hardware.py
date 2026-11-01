import importlib.util
import pathlib
import unittest

p=pathlib.Path(__file__).resolve().parents[1]/"scripts"/"inspect_adt_hardware.py"
spec=importlib.util.spec_from_file_location("inspect_adt_hardware",p)
mod=importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

class Node:
    def __init__(self,name,compatible=b"",children=()):
        self.props={"name":name,"compatible":compatible}
        self.children=list(children)

class ADTTests(unittest.TestCase):
    def test_actual_hardware_names(self):
        tree=Node(b"root",children=[
            Node(b"arm-io",children=[
                Node(b"nand-controller",b"apple,ans2",()),
                Node(b"display0",b"apple,dcp",()),
                Node(b"usb0",b"apple,xhci",()),
                Node(b"speaker-amp",b"apple,i2s",()),
            ])
        ])
        report=mod.report(mod.candidates(tree))
        self.assertGreaterEqual(report["category_counts"]["storage"],1)
        self.assertGreaterEqual(report["category_counts"]["display_gpu"],1)
        self.assertGreaterEqual(report["category_counts"]["usb_input"],1)
        self.assertGreaterEqual(report["category_counts"]["audio"],1)
        self.assertFalse(report["real_homeview_gui_booted"])
    def test_binary_property_safely_decoded(self):
        self.assertEqual(mod.as_string(b"ans2\0extra"),"ans2")

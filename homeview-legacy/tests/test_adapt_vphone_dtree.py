import importlib.util
from pathlib import Path
import unittest

PATH = Path(__file__).resolve().parents[1] / "scripts" / "adapt_vphone_dtree.py"
spec = importlib.util.spec_from_file_location("adapt_vphone_dtree", PATH)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


class Node:
    def __init__(self):
        self.children = []
        self.props = {"name": "arm-io"}

    def remove_child(self, child_name):
        raise ValueError("child %s not found" % child_name)


class AdaptVPhoneTreeTests(unittest.TestCase):
    def test_missing_uart_is_skipped(self):
        skipped = mod.tolerate_missing_children(Node)
        Node().remove_child("dockchannel-uart")
        self.assertEqual(skipped, ["dockchannel-uart"])


if __name__ == "__main__":
    unittest.main()

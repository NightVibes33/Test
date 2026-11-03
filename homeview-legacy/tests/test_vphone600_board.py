import importlib.util
from pathlib import Path
import unittest

PATH = Path(__file__).resolve().parents[1] / "scripts" / "vphone600_board.py"
spec = importlib.util.spec_from_file_location("vphone600_board", PATH)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


class VPhone600BoardTests(unittest.TestCase):
    def test_tree_uses_gic_and_apple_virtio_not_a_linear_framebuffer(self):
        board = mod.board()
        self.assertFalse(board["darwin_aic_present"])
        self.assertEqual(board["interrupt_controller"], "arm-io/gic")
        self.assertEqual(board["machine_name"], "vresearch101")
        self.assertIn("ARM,gicv3", board["gic"]["compatible"])
        self.assertEqual(
            [region["guest_physical"] for region in board["gic"]["regions"]],
            [0x10000000, 0x10010000, 0x1FFF0000],
        )
        names = {item["name"]: item for item in board["devices"]}
        self.assertEqual(names["uart0"]["compatible"], "arm,pl011")
        self.assertEqual(names["uart0"]["windows"][0]["child_base"], 0x10010000)
        self.assertEqual(names["uart0"]["windows"][0]["guest_physical"], 0x20010000)
        self.assertEqual(names["gfx"]["compatible"], "paravirtualizedgraphics,gpu")
        self.assertEqual(names["gfx"]["windows"][0]["guest_physical"], 0x30200000)
        self.assertEqual(names["gfx"]["spi"], [0x11])
        self.assertEqual(names["pcie"]["compatible"], "pcie,vmapple1")
        self.assertEqual(names["pcie"]["windows"][0]["guest_physical"], 0x40000000)
        self.assertTrue(board["addresses_match_vresearch101"])
        self.assertFalse(board["root_disk"]["generic_virtio_mmio_is_the_binding"])
        self.assertEqual(board["root_disk"]["qemu_backend_id"], "root-pci")
        self.assertFalse(board["display"]["linear_bootloader_framebuffer"])
        self.assertEqual(board["display"]["vram_reg_size"], 0)
        self.assertEqual(board["display"]["guest_physical"], 0x30200000)


if __name__ == "__main__":
    unittest.main()

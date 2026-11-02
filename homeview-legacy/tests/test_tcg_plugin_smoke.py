import importlib.util
from pathlib import Path
import tempfile
import unittest

P = Path(__file__).resolve().parents[1] / "scripts" / "smoke_homeview_tcg_plugin.py"
spec = importlib.util.spec_from_file_location("smoke_homeview_tcg_plugin", P)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


class SmokeArgumentsTests(unittest.TestCase):
    def test_command_enables_actual_qemu_plugin_output(self):
        cmd = mod.command(Path("/tmp/qemu-system-aarch64"),
                          Path("/tmp/observer.dylib"), Path("/tmp/trace.log"))
        self.assertEqual(cmd[cmd.index("-d") + 1], "plugin")
        self.assertEqual(cmd[cmd.index("-M") + 1], "none")
        self.assertEqual(cmd[cmd.index("-plugin") + 1],
                         "/tmp/observer.dylib,addr=0xfffffff009b0dabc")
        self.assertIn("-S", cmd)
        self.assertNotIn("-bootkc", cmd)
        self.assertNotIn("-dtree", cmd)

    def test_missing_executable_or_plugin_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            with self.assertRaisesRegex(ValueError, "missing"):
                mod.verify(Path(d) / "qemu", Path(d) / "observer")

    def test_smoke_marker_not_conflated_with_guest_execution(self):
        self.assertIn("initialized targets=1 signatures=0 read_only=true", mod.MARKER)
        self.assertNotIn(" hit ", mod.MARKER)
        smoke = P.read_text()
        self.assertIn("independent_PC_trace_file_verified", smoke)
        self.assertIn("HOMEVIEW_TCG_PC_TRACE_FILE", smoke)
        self.assertIn("MARKER not in direct", smoke)

if __name__ == "__main__":
    unittest.main()

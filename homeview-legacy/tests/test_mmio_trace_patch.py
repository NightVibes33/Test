import importlib.util
import pathlib
import unittest

p=pathlib.Path(__file__).resolve().parents[1]/"scripts"/"patch_qemu_mmio_trace.py"
spec=importlib.util.spec_from_file_location("patch_qemu_mmio_trace",p)
module=importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class TraceTests(unittest.TestCase):
    def test_tracer_is_opt_in_and_capped(self):
        source=(
            '#include "hw/intc/apple_aic.h"\n'
            'static void init_sep(void) {}\n'
            '    init_sep(dt_root);\n    init_cpu_impl(dt_root);\n'
        )
        changed=module.patch(source)
        self.assertIn('g_getenv("HOMEVIEW_MMIO_TRACE")',changed)
        self.assertIn('HV_TRACE_LIMIT 96',changed)
        self.assertIn('arm-io/dcp',changed)
        self.assertIn('arm-io/ans',changed)
        self.assertEqual(module.patch(changed),changed)
    def test_unknown_source_rejected(self):
        with self.assertRaises(ValueError):
            module.patch('unrelated')

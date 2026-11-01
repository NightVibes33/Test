import importlib.util
import pathlib
import unittest

target = pathlib.Path(__file__).resolve().parents[1] / 'scripts' / 'probe_apple_ota.py'
spec = importlib.util.spec_from_file_location('probe_apple_ota', target)
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)

class FakeResponse:
    status = 206
    headers = {'Content-Range': 'bytes 0-63/6509559808', 'Content-Type': 'application/octet-stream'}
    def __enter__(self): return self
    def __exit__(self, *args): pass
    def read(self, count): return b'AEA1' + b'\x00' * (count - 4)

class OTAProbeTests(unittest.TestCase):
    def setUp(self):
        self.catalog = (
            '.init( productType: "HomeAccessory17,1", version: "27.2", build: "24V514", '
            'url: "https://updates.cdn-apple.com/foo/bar.aea", size: 6_509_559_808, key: "unused" )'
        )
    def test_catalog_identity(self):
        self.assertEqual(probe.find_official_asset(self.catalog),
            ('https://updates.cdn-apple.com/foo/bar.aea', 6509559808))
    def test_reject_untrusted_source(self):
        with self.assertRaises(ValueError):
            probe.find_official_asset(self.catalog.replace('updates.cdn-apple.com', 'example.com'))
    def test_reject_different_build(self):
        with self.assertRaises(ValueError):
            probe.find_official_asset(self.catalog.replace('24V514', '24V000'))
    def test_reject_incorrect_size(self):
        with self.assertRaises(ValueError):
            probe.find_official_asset(self.catalog.replace('6_509_559_808', '5'))
    def test_range_and_magic(self):
        def fake(req, timeout):
            self.assertEqual(req.get_header('Range'), 'bytes=0-63')
            return FakeResponse()
        result = probe.check_asset('https://updates.cdn-apple.com/foo/bar.aea', 6509559808, fake)
        self.assertTrue(result['aea_magic_verified'])
        self.assertFalse(result['homeview_booted_on_intel'])
    def test_not_partial(self):
        class Bad(FakeResponse): status=200
        with self.assertRaises(ValueError):
            probe.check_asset('https://updates.cdn-apple.com/foo/bar.aea', 6509559808,
                lambda req, timeout: Bad())

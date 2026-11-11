import ast, pathlib, plistlib, sys, unittest, zipfile, tempfile, struct
PATH=pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0,str(PATH/'scripts'))
from patch_pairing import APP,FRAMEWORK,INSTALL_NAME,append_load_command
class PairingTests(unittest.TestCase):
    def test_no_wifi_swizzling(self):
        s=(PATH/'src/CarCastPairing.m').read_text()
        self.assertIn('tunnel_create_rppairing',s)
        self.assertIn('rp_pairing_file_from_bytes',s)
        self.assertIn('UIDocumentPickerViewController',s)
        self.assertNotIn('method_setImplementation',s)
        self.assertNotIn('CCSyntheticNetwork',s)
        self.assertIn('NSFileProtectionCompleteUntilFirstUserAuthentication',s)
    def test_repacker_rejects_nonrunnable_extension(self):
        from patch_pairing import package
        from pathlib import Path
        import tempfile
        with tempfile.TemporaryDirectory() as temp:
            path=Path(temp)
            # A loadable MH_BUNDLE (type 8) must never ship as an .appex.
            payload=bytearray(4096)
            struct.pack_into('<IIIIIIII',payload,0,0xfeedfacf,0x0100000c,0,8,0,0,0,0)
            bundle=path/'invalid-extension'
            bundle.write_bytes(payload)
            with self.assertRaisesRegex(ValueError,'MH_EXECUTE'):
                package(path/'ignored.ipa',path/'ignored.framework',bundle,path/'out.ipa',path/'audit.json')

    def test_built_in_vpn_not_faked(self):
        s=(PATH/'src/CarCastLocalTunnel.m').read_text()
        self.assertIn('NEPacketTunnelProvider',s)
        self.assertIn('readPacketsWithCompletionHandler',s)
        self.assertIn('writePackets',s)
        p=plistlib.loads((PATH/'Tunnel.entitlements').read_bytes())
        self.assertIn('packet-tunnel-provider',p['com.apple.developer.networking.networkextension'])
    def test_manifest_requests_are_explicit(self):
        p=(PATH/'scripts/patch_pairing.py').read_text()
        self.assertIn('wifi_free_carplay_verified',p)
        self.assertIn('local_vpn_entitlement_granted',p)
        self.assertIn('_remotepairing._tcp',p)
if __name__=='__main__':unittest.main()

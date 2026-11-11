import os
import plistlib
import struct
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'))
from patch_diagnostics import APP, INSTALL_NAME, append_load_command, commands, package


def fake_macho(cryptid=0):
    header=bytearray(0x6000)
    # mach_header_64: filetype execute, ncmds=2, sizeofcmds=176
    struct.pack_into('<IIIIIIII',header,0,0xfeedfacf,0x0100000c,0,2,2,176,0x00200085,0)
    segment=32
    struct.pack_into('<II16sQQQQIIII',header,segment,0x19,152,b'__TEXT',0x100000000,0x6000,0,0x6000,7,5,1,0)
    section=segment+72
    struct.pack_into('<16s16sQQIIIIIIII',header,section,b'__text',b'__TEXT',0x100004000,0x2000,0x4000,2,0,0,0x80000400,0,0,0)
    crypto=segment+152
    struct.pack_into('<IIIIII',header,crypto,0x2c,24,0x4000,0x1000,cryptid,0)
    header[0x4000:0x5000]=b'\x20\x00\x80\xd2'*(0x1000//4)
    return bytes(header)


class RepackageTests(unittest.TestCase):
    def test_runtime_entitlement_inspection_is_read_only(self):
        source=(Path(__file__).resolve().parents[1]/'src'/'CarCastDiagnosticsOnly.m').read_text()
        self.assertIn('SecTaskCopyValueForEntitlement',source)
        self.assertIn('SecTaskCreateFromSelf',source)
        self.assertIn('PRESENT_NON_BOOLEAN',source)
        self.assertIn('NOT_QUERYABLE',source)
        self.assertIn('NOT_REPORTED',source)
        self.assertNotIn('SecItemAdd(',source)
        self.assertNotIn('method_setImplementation',source)

    def test_network_methods_untouched(self):
        source=(Path(__file__).resolve().parents[1]/'src'/'CarCastDiagnosticsOnly.m').read_text()
        self.assertIn('CCReadOnlyWiFiProbe',source)
        self.assertNotIn('method_setImplementation',source)
        self.assertNotIn('class_createInstance',source)
        self.assertNotIn('CCSyntheticNetwork',source)
        self.assertIn('Documents/CarCastDebug',source)

    def test_add_load_command_does_not_change_text(self):
        src=fake_macho()
        patched,p=append_load_command(src)
        self.assertEqual(len(patched),len(src))
        self.assertEqual(src[0x4000:],patched[0x4000:])
        self.assertIn(INSTALL_NAME.encode(), patched)
        self.assertEqual(len(commands(patched)),3)
        self.assertGreaterEqual(p['header_padding_end'],0x4000)

    def test_encrypted_source_refused(self):
        with tempfile.TemporaryDirectory() as work:
            path=Path(work);ipa=path/'encrypted.ipa';shim=path/'shim';out=path/'output.ipa'
            self._fixture(ipa,fake_macho(cryptid=1))
            shim.write_bytes(fake_macho())
            with self.assertRaisesRegex(ValueError,'not been fully decrypted'):
                package(ipa,shim,out,path/'manifest.json')
            self.assertFalse(out.exists())

    def test_preserves_every_original_resource_and_modes(self):
        with tempfile.TemporaryDirectory() as work:
            path=Path(work);ipa=path/'original.ipa';shim=path/'shim';out=path/'output.ipa'
            self._fixture(ipa,fake_macho())
            shim.write_bytes(fake_macho())
            manifest=package(ipa,shim,out,path/'manifest.json')
            self.assertTrue(manifest['original_resources_except_executable_and_files_plist_preserved'])
            self.assertFalse(manifest['network_entitlements_automatically_granted'])
            with zipfile.ZipFile(ipa) as z0,zipfile.ZipFile(out) as z1:
                self.assertEqual(z1.testzip(),None)
                self.assertIn(APP+'Frameworks/CarCastAirPlay.framework/CarCastAirPlay',z1.namelist())
                self.assertEqual(z1.getinfo(APP+'CarCast').external_attr,z0.getinfo(APP+'CarCast').external_attr)
                info0=plistlib.loads(z0.read(APP+'Info.plist'))
                info1=plistlib.loads(z1.read(APP+'Info.plist'))
                self.assertTrue(info1['UIFileSharingEnabled'])
                self.assertTrue(info1['LSSupportsOpeningDocumentsInPlace'])
                for key,value in info0.items():
                    self.assertEqual(info1[key],value)
                self.assertEqual(manifest['diagnostic_directory'],'Documents/CarCastDebug')
                self.assertTrue(z1.getinfo(APP+'Frameworks/CarCastDiagnosticsOnly.framework/CarCastDiagnosticsOnly').external_attr>>16 & 0o111)
            with self.assertRaisesRegex(ValueError,'Refusing to overwrite'):
                package(ipa,shim,out,path/'manifest2.json')

    def test_original_files_plist_bytes_preserved(self):
        with tempfile.TemporaryDirectory() as work:
            path=Path(work); initial=path/'initial.ipa'; ready=path/'ready.ipa'
            output=path/'output.ipa'; shim=path/'shim'
            self._fixture(initial,fake_macho())
            with zipfile.ZipFile(initial) as src, zipfile.ZipFile(ready,'w') as dest:
                for entry in src.infolist():
                    body=src.read(entry)
                    if entry.filename == APP+'Info.plist':
                        info=plistlib.loads(body)
                        info['UIFileSharingEnabled']=True
                        info['LSSupportsOpeningDocumentsInPlace']=True
                        body=plistlib.dumps(info,fmt=plistlib.FMT_XML)
                    dest.writestr(entry,body)
            shim.write_bytes(fake_macho())
            package(ready,shim,output,path/'manifest.json')
            with zipfile.ZipFile(ready) as before, zipfile.ZipFile(output) as after:
                self.assertEqual(before.read(APP+'Info.plist'),after.read(APP+'Info.plist'))

    def test_reject_second_injection(self):
        with tempfile.TemporaryDirectory() as work:
            path=Path(work);ipa=path/'input.ipa';shim=path/'shim';out=path/'output.ipa'
            self._fixture(ipa,fake_macho())
            shim.write_bytes(fake_macho())
            package(ipa,shim,out,path/'manifest.json')
            with self.assertRaisesRegex(ValueError,'already packaged'):
                package(out,shim,path/'again.ipa',path/'again.json')

    def _fixture(self,ipa,binary):
        with zipfile.ZipFile(ipa,'w') as z:
            info=plistlib.dumps({'CFBundleIdentifier':'ai.rplay.carcast.ios','CFBundleExecutable':'CarCast','NSLocalNetworkUsageDescription':'test'})
            for name,data,mode in [
                (APP+'Info.plist',info,0o100644),
                (APP+'CarCast',binary,0o100755),
                (APP+'Frameworks/CarCastAirPlay.framework/CarCastAirPlay',b'framework data',0o100755),
                (APP+'Assets.car',b'asset data',0o100644),
            ]:
                item=zipfile.ZipInfo(name)
                item.external_attr=mode<<16; item.create_system=3
                z.writestr(item,data)

if __name__ == '__main__': unittest.main()
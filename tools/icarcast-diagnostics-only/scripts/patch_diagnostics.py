#!/usr/bin/env python3
"""Repackage a *user supplied, legitimately decrypted* iCarCast IPA for SideStore.

The original IPA must already contain a verified decrypted CarCast executable (cryptid 0).
This script adds a separately signed, small diagnostic-only framework framework and only
one LC_LOAD_DYLIB record in the main executable. It never reads FairPlay keys,
never modifies original assets, and does not change granted entitlements.
"""
import argparse
import copy
import hashlib
import json
import os
import plistlib
import struct
import sys
import zipfile
from pathlib import Path

MAGIC_64_LE = 0xfeedfacf
LC_LOAD_DYLIB = 0xC
LC_CODE_SIGNATURE = 0x1D
APP = 'Payload/CarCast.app/'
FRAMEWORK = 'CarCastDiagnosticsOnly.framework'
INSTALL_NAME = '@rpath/' + FRAMEWORK + '/CarCastDiagnosticsOnly'
LINK_SUFFIX = 'Frameworks/' + FRAMEWORK + '/CarCastDiagnosticsOnly'


def sha256(blob):
    return hashlib.sha256(blob).hexdigest()


def commands(binary):
    if len(binary) < 32 or struct.unpack_from('<I', binary)[0] != MAGIC_64_LE:
        raise ValueError('The main executable is not a supported thin ARM64 Mach-O')
    if struct.unpack_from('<I', binary, 4)[0] != 0x100000c:
        raise ValueError('The main executable is not ARM64')
    ncmds, sizeofcmds = struct.unpack_from('<II', binary, 16)
    pos = 32
    result = []
    for _ in range(ncmds):
        if pos + 8 > 32 + sizeofcmds:
            raise ValueError('Malformed load commands')
        cmd, cmdsize = struct.unpack_from('<II', binary, pos)
        if cmdsize < 8 or pos + cmdsize > 32 + sizeofcmds:
            raise ValueError('Invalid load command size')
        result.append((pos, cmd, cmdsize))
        pos += cmdsize
    if pos != 32 + sizeofcmds:
        raise ValueError('Mismatch in load command count')
    return result


def make_load_command(name):
    data = name.encode('ascii') + b'\0'
    size = (24 + len(data) + 7) & ~7
    return struct.pack('<IIIIII', LC_LOAD_DYLIB, size, 24, 1, 0x10000, 0x10000) + data + bytes(size - 24 - len(data))


def append_load_command(exe):
    data = bytearray(exe)
    cmds = commands(data)
    if any(cmd in (LC_LOAD_DYLIB, LC_LOAD_DYLIB | 0x80000000) and INSTALL_NAME.encode() in data[off:off+length] for off, cmd, length in cmds):
        raise ValueError('diagnostic-only framework is already linked')
    # We may only insert into header padding. Never shift encrypted pages,
    # Mach-O segment offsets, code, or the LINKEDIT region.
    first_text_offset = 1 << 63
    for off, cmd, length in cmds:
        if cmd == 0x19: # LC_SEGMENT_64
            segment_name = bytes(data[off+8:off+24]).split(b'\0')[0]
            if segment_name == b'__TEXT':
                nsects = struct.unpack_from('<I', data, off+64)[0]
                for i in range(nsects):
                    s = off+72+i*80
                    if s+80 > off+length: raise ValueError('Malformed section table')
                    offset = struct.unpack_from('<I', data, s+48)[0]
                    if offset and offset < first_text_offset:
                        first_text_offset = offset
    if first_text_offset == 1 << 63:
        raise ValueError('Cannot identify first __TEXT section')
    ncmds, size = struct.unpack_from('<II', data, 16)
    injection = 32+size
    new_cmd = make_load_command(INSTALL_NAME)
    if injection+len(new_cmd) > first_text_offset:
        raise ValueError('Insufficient Mach-O header padding')
    if any(data[injection:injection+len(new_cmd)]):
        raise ValueError('Mach-O header padding is not zero; refusing to overwrite')
    data[injection:injection+len(new_cmd)] = new_cmd
    struct.pack_into('<II', data, 16, ncmds+1, size+len(new_cmd))
    # Any previous signature is cryptographically invalid after changes,
    # and must be replaced by SideStore with an authorized profile.
    # A stale LC_CODE_SIGNATURE points at an old signature; SideStore will
    # rewrite it. Do not tamper with CodeDirectory or fake entitlements here.
    assert INSTALL_NAME.encode() in data[injection:injection+len(new_cmd)]
    assert len(data) == len(exe)
    return bytes(data), {'load_command_offset': injection, 'load_command_bytes':len(new_cmd), 'header_padding_end':first_text_offset}


def package(input_path, shim_path, output_path, manifest_path):
    shim = Path(shim_path).read_bytes()
    if len(shim) < 4096 or not shim.startswith(b'\xcf\xfa\xed\xfe'):
        raise ValueError('Compiled iOS arm64 Mach-O dynamic framework is required')
    if Path(input_path).resolve() == Path(output_path).resolve():
        raise ValueError('Refusing to overwrite input IPA')
    if Path(output_path).exists():
        raise ValueError('Refusing to overwrite existing output')
    fw_info = plistlib.dumps({
        'CFBundleDevelopmentRegion':'en',
        'CFBundleExecutable':'CarCastDiagnosticsOnly',
        'CFBundleIdentifier':'ai.rplay.carcast.ios.diagnostics-only',
        'CFBundleInfoDictionaryVersion':'6.0',
        'CFBundleName':'CarCastDiagnosticsOnly',
        'CFBundlePackageType':'FMWK',
        'CFBundleShortVersionString':'1.0.0',
        'CFBundleVersion':'1',
        'MinimumOSVersion':'18.0',
        'DTPlatformName':'iphoneos',
    }, fmt=plistlib.FMT_BINARY)
    with zipfile.ZipFile(input_path) as source:
        all_names = source.namelist()
        if len(set(all_names)) != len(all_names):
            raise ValueError('Duplicate ZIP members in source IPA')
        target = APP+'CarCast'
        if target not in all_names: raise ValueError('CarCast executable missing')
        if any(name.startswith(APP+'Frameworks/'+FRAMEWORK+'/') for name in all_names):
            raise ValueError('Diagnostics already packaged')
        info = plistlib.loads(source.read(APP+'Info.plist'))
        if info.get('CFBundleExecutable') != 'CarCast':
            raise ValueError('Unexpected main executable')
        # Both flags expose the app's own Documents directory in Files.
        # Neither flag grants external sandbox or code-bundle access.
        original_info_bytes = source.read(APP+'Info.plist')
        if info.get('UIFileSharingEnabled') is True and info.get('LSSupportsOpeningDocumentsInPlace') is True:
            # Preserve the exact original bytes if Files access is already enabled.
            files_info = original_info_bytes
        else:
            info['UIFileSharingEnabled'] = True
            info['LSSupportsOpeningDocumentsInPlace'] = True
            format_kind = plistlib.FMT_BINARY if original_info_bytes.startswith(b'bplist00') else plistlib.FMT_XML
            files_info = plistlib.dumps(info, fmt=format_kind, sort_keys=False)
        original_bin = source.read(target)
        # Find and require LC_ENCRYPTION_INFO_64 cryptid 0.
        info_commands = [(off, cmd, length) for off, cmd, length in commands(original_bin) if cmd == 0x2c]
        if len(info_commands) != 1 or struct.unpack_from('<I', original_bin, info_commands[0][0]+16)[0] != 0:
            raise ValueError('The input IPA has not been fully decrypted (cryptid != 0)')
        patched, patch = append_load_command(original_bin)
        output_path = Path(output_path)
        output_path.parent.mkdir(parents=True,exist_ok=True)
        try:
            with zipfile.ZipFile(output_path,'w') as dest:
                for item in source.infolist():
                    content = source.read(item.filename)
                    if item.filename == target: content = patched
                    if item.filename == APP+'Info.plist': content = files_info
                    # Avoid copying old signatures when adding a framework.
                    # SideStore will create new CodeResources and CodeDirectories.
                    if '/_CodeSignature/' in item.filename:
                        continue
                    dest.writestr(copy.copy(item), content)
                for suffix, content, is_executable in [
                    ('Info.plist',fw_info,False),
                    ('CarCastDiagnosticsOnly',shim,True),
                ]:
                    name=APP+'Frameworks/'+FRAMEWORK+'/'+suffix
                    entry=zipfile.ZipInfo(name)
                    entry.compress_type=zipfile.ZIP_DEFLATED
                    entry.create_system=3
                    entry.external_attr=(0o100755 if is_executable else 0o100644)<<16
                    dest.writestr(entry, content)
            with zipfile.ZipFile(output_path) as check:
                assert check.testzip() is None
                assert check.read(target)==patched
                assert check.read(APP+LINK_SUFFIX)==shim
                assert len(set(check.namelist()))==len(check.namelist())
                for entry in source.infolist():
                    if '/_CodeSignature/' in entry.filename or entry.filename in (target, APP+'Info.plist'): continue
                    assert check.read(entry.filename)==source.read(entry.filename)
                assert commands(check.read(target))[-1][1] == LC_LOAD_DYLIB
                shared_info = plistlib.loads(check.read(APP+'Info.plist'))
                assert shared_info.get('UIFileSharingEnabled') is True
                assert shared_info.get('LSSupportsOpeningDocumentsInPlace') is True
                original_info = plistlib.loads(source.read(APP+'Info.plist'))
                assert all(shared_info[k] == v for k, v in original_info.items()
                           if k not in ('UIFileSharingEnabled', 'LSSupportsOpeningDocumentsInPlace'))
            manifest = {
                'input_sha256': sha256(Path(input_path).read_bytes()),
                'output_sha256': sha256(output_path.read_bytes()),
                'patch':patch,
                'main_executable_sha256_before':sha256(original_bin),
                'main_executable_sha256_after':sha256(patched),
                'original_entries':len(all_names),
                'output_entries':len(zipfile.ZipFile(output_path).namelist()),
                'original_resources_except_executable_and_files_plist_preserved':True,
                'Files_Documents_visible_after_first_launch':True,
                'diagnostic_directory':'Documents/CarCastDebug',
                'diagnostic_capture':'app lifecycle, network path, Wi-Fi lookup, hotspot callbacks, stdout/stderr; excludes system-wide unified logs',
                'network_entitlements_automatically_granted':False,
                'original_network_methods_swizzled':False,
                'device_wi_fi_verified':False,
                'requires_valid_provisioning':True,
            }
            Path(manifest_path).write_text(json.dumps(manifest,indent=2)+'\n')
        except Exception:
            output_path.unlink(missing_ok=True)
            raise
    return manifest


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input',required=True)
    parser.add_argument('--framework',required=True,help='iOS arm64 dynamic framework binary')
    parser.add_argument('--output',required=True)
    parser.add_argument('--manifest',required=True)
    args=parser.parse_args()
    print(json.dumps(package(args.input,args.framework,args.output,args.manifest),indent=2))

if __name__=='__main__':main()
#!/usr/bin/env python3
"""Package a REAL, complete modern Music.app extracted from matching IPSW.

No iOS 15 fallback, no FairPlay decryption, no Apple-private entitlement spoofing.
"""
import argparse
import hashlib
import json
import plistlib
import struct
import stat
import zipfile
from pathlib import Path

MACHO={b'\xcf\xfa\xed\xfe':('<',True), b'\xce\xfa\xed\xfe':('<',False),
       b'\xfe\xed\xfa\xcf':('>',True), b'\xfe\xed\xfa\xce':('>',False)}
FAT={b'\xca\xfe\xba\xbe':('>',False), b'\xbe\xba\xfe\xca':('<',False),
     b'\xca\xfe\xba\xbf':('>',True), b'\xbf\xba\xfe\xca':('<',True)}

def mach_info(buf):
    if len(buf)<4:return None
    magic=buf[:4]
    if magic in FAT:
        endian,fat64=FAT[magic]
        if len(buf)<8:raise ValueError('Bad FAT header')
        n=struct.unpack_from(endian+'I',buf,4)[0]
        if not 0<n<=32:raise ValueError('Bad FAT arch count')
        off=8;found=[]
        for _ in range(n):
            width=32 if fat64 else 20
            if off+width>len(buf):raise ValueError('Truncated FAT arch')
            start,size=struct.unpack_from(endian+('QQ' if fat64 else 'II'),buf,off+8)
            if size==0 or start+size>len(buf):raise ValueError('Invalid FAT slice')
            found.extend(mach_info(buf[start:start+size]) or [])
            off+=width
        return found
    if magic not in MACHO:return None
    endian,is64=MACHO[magic];header=32 if is64 else 28
    if len(buf)<header:raise ValueError('Short Mach-O')
    cpu=struct.unpack_from(endian+'I',buf,4)[0]
    n,total=struct.unpack_from(endian+'II',buf,16)
    if n>10000 or total+header>len(buf):raise ValueError('Invalid commands')
    off=header;cryptids=[];platforms=[]
    for _ in range(n):
        if off+8>header+total:raise ValueError('Short command')
        cmd,size=struct.unpack_from(endian+'II',buf,off)
        if size<8 or off+size>header+total:raise ValueError('Invalid command')
        if cmd in (0x21,0x2c):
            if size<20:raise ValueError('Short encryption command')
            cryptids.append(struct.unpack_from(endian+'I',buf,off+16)[0])
        if cmd==0x32 and size>=24:platforms.append(struct.unpack_from(endian+'I',buf,off+8)[0])
        off+=size
    return [{'cpu':cpu,'platforms':platforms,'cryptids':cryptids,
             'encrypted':any(v!=0 for v in cryptids)}]

def sha(data):return hashlib.sha256(data).hexdigest()

def build(args):
    parent=args.extracted
    if parent.name=='Music.app' and parent.is_dir():candidates=[parent]
    else:candidates=[c for c in parent.rglob('Music.app') if c.is_dir()]
    candidates=[c for c in candidates if (c/'Info.plist').is_file()]
    if len(candidates)!=1:
        raise ValueError(f'Expected exactly one complete Music.app, got {len(candidates)}')
    app=candidates[0]
    p=plistlib.loads((app/'Info.plist').read_bytes())
    if p.get('CFBundleIdentifier')!='com.apple.Music':
        raise ValueError('Source is not an original Apple Music.app')
    exe=p.get('CFBundleExecutable')
    if not isinstance(exe,str) or not exe or '/' in exe or not (app/exe).is_file():
        raise ValueError('Missing native Music executable')
    original=(app/exe).read_bytes()
    mi=mach_info(original)
    if not mi or any(s['encrypted'] or s['cpu'] not in (0x100000c,0x100000e)
                     or 7 in s['platforms'] for s in mi):
        raise ValueError('Main binary is encrypted or not iOS device arm64')
    packaged={};encrypted=[];simulator=[];extensions=[]
    for f in app.rglob('*'):
        if f.is_symlink():raise ValueError('Symlink in source: '+str(f))
        if not f.is_file():continue
        rel=f.relative_to(app).as_posix()
        if any(x in ('_CodeSignature','SC_Info') for x in rel.split('/')):continue
        if rel=='embedded.mobileprovision':continue
        if args.main_only and rel.startswith('PlugIns/'):continue
        data=f.read_bytes()
        if f.name=='Info.plist':
            info=plistlib.loads(data)
            ident=info.get('CFBundleIdentifier')
            if rel=='Info.plist':
                info['CFBundleIdentifier']=args.bundle_id
                info['CFBundleDisplayName']='Music Native 27 (Test)'
                info['MinimumOSVersion']='27.0'
            elif '.appex/' in rel and isinstance(ident,str) and ident.startswith('com.apple.Music'):
                info['CFBundleIdentifier']=args.bundle_id+ident[len('com.apple.Music'):]
                extensions.append(info['CFBundleIdentifier'])
            data=plistlib.dumps(info)
        m=mach_info(data)
        if m:
            if any(s['encrypted'] for s in m):encrypted.append(rel)
            if any(7 in s['platforms'] for s in m):simulator.append(rel)
        packaged['Payload/Music.app/'+rel]=(data,f.stat().st_mode)
    if encrypted:raise ValueError(f'Encrypted binaries: {encrypted[:5]}')
    if simulator:raise ValueError(f'Simulator binaries: {simulator[:5]}')
    if len(packaged)<10:raise ValueError('Implausibly few app files: '+str(len(packaged)))
    if args.output.exists():raise ValueError('Output already exists (no overwrite)')
    args.output.parent.mkdir(parents=True,exist_ok=True)
    with zipfile.ZipFile(args.output,'w',zipfile.ZIP_DEFLATED,compresslevel=7) as z:
        for name,(data,mode) in sorted(packaged.items()):
            entry=zipfile.ZipInfo(name)
            entry.create_system=3
            entry.compress_type=zipfile.ZIP_DEFLATED
            entry.external_attr=(stat.S_IFREG | stat.S_IMODE(mode))<<16
            z.writestr(entry,data,compress_type=zipfile.ZIP_DEFLATED,compresslevel=7)
    with zipfile.ZipFile(args.output) as z:
        if z.testzip():raise ValueError('IPA CRC mismatch')
    report={'status':'unsigned_structural_pass_only',
      'origin':'Matching iOS 27 official IPSW extracted native Music.app only',
      'expected_build_from_workflow':args.expected_build,
      'no_ios15_binary_used':True,
      'original_bundle_id':'com.apple.Music',
      'prepared_bundle_id':args.bundle_id,
      'main_executable_sha256':sha(original),
      'main_macho':mi,
      'files':len(packaged),
      'extension_bundle_ids':extensions,
      'ipa_sha256':sha(args.output.read_bytes()),
      'ipa_size':args.output.stat().st_size,
      'limitations':['No FairPlay bypass','No Apple-private entitlements granted',
        'Unsigned; SideStore signing may fail','Installation/launch/playback unverified']}
    args.output.with_suffix('.report.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,indent=2))

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--extracted',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--bundle-id',default='com.nightvibes33.music.native27')
    parser.add_argument('--main-only',action='store_true')
    parser.add_argument('--expected-build',default='24A446')
    a=parser.parse_args()
    try:build(a)
    except (ValueError,OSError,plistlib.InvalidFileException) as e:
        raise SystemExit('BLOCKED: '+str(e))

#!/usr/bin/env python3
"""Rebuild the original iCarCast IPA around a verified decrypted Mach-O, without injected code."""
import argparse
from copy import copy
import hashlib
import json
from pathlib import Path
import plistlib
import struct
import sys
import zipfile

EXECUTABLE = "Payload/CarCast.app/CarCast"
INFO = "Payload/CarCast.app/Info.plist"
AIRPLAY = "Payload/CarCast.app/Frameworks/CarCastAirPlay.framework/CarCastAirPlay"
EXCLUDED_DIRS = (
    "Payload/CarCast.app/SC_Info/",
    "Payload/CarCast.app/_CodeSignature/",
    "Payload/CarCast.app/Frameworks/CarCastAirPlay.framework/_CodeSignature/",
)
ZIP_PROPERTIES = ("date_time", "compress_type", "create_system", "external_attr",
                  "internal_attr", "extra", "comment")

def encryption_info(binary):
    if len(binary) < 32 or binary[:4] != b"\xcf\xfa\xed\xfe":
        raise ValueError("Expected iCarCast 64-bit little-endian Mach-O")
    ncmds, sizecmds = struct.unpack_from("<II", binary, 16)
    if not (0 < ncmds < 1000 and 0 < sizecmds <= len(binary)-32):
        raise ValueError("Invalid Mach-O load commands")
    pos = 32
    enc = []
    for _ in range(ncmds):
        if pos + 8 > 32+sizecmds:
            raise ValueError("Truncated load command")
        cmd, size = struct.unpack_from("<II", binary, pos)
        if size < 8 or pos + size > 32+sizecmds:
            raise ValueError("Invalid load command size")
        if cmd == 0x2c:
            if size < 24:
                raise ValueError("Short encryption info")
            cryptoff, cryptsize, cryptid = struct.unpack_from("<III",binary,pos+8)
            if cryptoff > len(binary) or cryptsize > len(binary)-cryptoff:
                raise ValueError("Invalid encrypted region bounds")
            enc.append((cryptoff,cryptsize,pos+16,cryptid))
        pos += size
    if len(enc) != 1:
        raise ValueError("Expected one encryption command")
    return enc[0]

def verify_macho(original, decrypted):
    if len(original) != len(decrypted):
        raise ValueError("Executable size differs from original")
    offset, size, id_offset, cryptid = encryption_info(original)
    if cryptid != 1 or encryption_info(decrypted) != (offset,size,id_offset,0):
        raise ValueError("Invalid cryptid transition")
    if not size or original[offset:offset+size] == decrypted[offset:offset+size]:
        raise ValueError("FairPlay ciphertext not decrypted")
    if not any(decrypted[offset:offset+size]):
        raise ValueError("Encrypted region zero-filled")
    for start,end in ((0,id_offset),(id_offset+4,offset),(offset+size,len(original))):
        if original[start:end] != decrypted[start:end]:
            raise ValueError("Executable changed outside FairPlay region or cryptid")
    return {"cryptoff":offset,"cryptsize":size,"cryptid_before":1,"cryptid_after":0}

def package(original_path,decrypted_path,output_path,report_path,files_access=True):
    for path in (original_path,decrypted_path):
        if not path.is_file():
            raise FileNotFoundError(path)
    if output_path.exists() or report_path.exists():
        raise FileExistsError("Refusing to overwrite an output")
    with zipfile.ZipFile(original_path) as original, zipfile.ZipFile(decrypted_path) as verified:
        original_names=original.namelist()
        if len(set(original_names)) != len(original_names):
            raise ValueError("Duplicate source ZIP entries")
        original_exe=original.read(EXECUTABLE)
        decrypted_exe=verified.read(EXECUTABLE)
        crypt=verify_macho(original_exe,decrypted_exe)
        if original.read(AIRPLAY) != verified.read(AIRPLAY):
            raise ValueError("Original and decrypted reference AirPlay frameworks differ")
        old_info=original.read(INFO)
        info=plistlib.loads(old_info)
        if info.get("CFBundleIdentifier") != "ai.rplay.carcast.ios":
            raise ValueError("Not the expected original iCarCast")
        if files_access:
            info["UIFileSharingEnabled"]=True
            info["LSSupportsOpeningDocumentsInPlace"]=True
            fmt=plistlib.FMT_BINARY if old_info.startswith(b"bplist00") else plistlib.FMT_XML
            new_info=plistlib.dumps(info,fmt=fmt,sort_keys=False)
        else:
            new_info=old_info
        skipped=[n for n in original_names if n.startswith(EXCLUDED_DIRS)]
        with zipfile.ZipFile(output_path,"w",allowZip64=True) as dest:
            dest.comment=original.comment
            for srcinfo in original.infolist():
                name=srcinfo.filename
                if name in skipped:
                    continue
                data=decrypted_exe if name==EXECUTABLE else new_info if name==INFO else original.read(srcinfo)
                dest.writestr(copy(srcinfo),data,compress_type=srcinfo.compress_type)
        with zipfile.ZipFile(output_path) as output:
            if output.testzip() is not None:
                raise ValueError("Output ZIP CRC failed")
            if set(output.namelist()) != set(original_names)-set(skipped):
                raise ValueError("Added or missing unexpected resources")
            modified=[]
            metadata=[]
            for item in output.infolist():
                reference=original.getinfo(item.filename)
                if output.read(item) != original.read(item.filename):
                    modified.append(item.filename)
                for field in ZIP_PROPERTIES:
                    if getattr(item,field) != getattr(reference,field):
                        metadata.append((item.filename,field))
            expected={EXECUTABLE,INFO} if files_access else {EXECUTABLE}
            if set(modified) != expected or metadata:
                raise ValueError("Unexpected file content or metadata changes")
            if any("CarCastWiFiFallback" in n or "CarCastDebug" in n for n in output.namelist()):
                raise ValueError("Injected framework found in minimal output")
            if output.getinfo(EXECUTABLE).external_attr>>16 != 0o100755:
                raise ValueError("Executable mode lost")
            if output.read(AIRPLAY) != original.read(AIRPLAY):
                raise ValueError("Original AirPlay framework changed")
    result={
        "source_sha256":hashlib.sha256(original_path.read_bytes()).hexdigest(),
        "output_sha256":hashlib.sha256(output_path.read_bytes()).hexdigest(),
        "source_entries":len(original_names),
        "output_entries":len(original_names)-len(skipped),
        "modified_content":modified,
        "omitted_obsolete_license_and_signature_entries":skipped,
        "added_resources":[],"injected_frameworks":[],
        "zip_metadata_changes":metadata,
        "decryption":crypt,"files_documents_visible":files_access,
        "SideStore_signing_required":True,
        "networking_entitlements_automatically_granted":False,
        "CarPlay_runtime_tested":False,
    }
    report_path.write_text(json.dumps(result,indent=2)+"\n")
    return result

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    for arg in ("original","decrypted","output","report"):
        parser.add_argument("--"+arg,required=True,type=Path)
    parser.add_argument("--no-files-access",action="store_true")
    args=parser.parse_args()
    try:
        print(json.dumps(package(args.original,args.decrypted,args.output,args.report,not args.no_files_access),indent=2))
    except Exception as exc:
        if args.output.exists():
            args.output.unlink()
        print("ERROR:",exc,file=sys.stderr)
        return 1
    return 0

if __name__=="__main__":
    sys.exit(main())

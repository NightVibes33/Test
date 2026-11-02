#!/usr/bin/env python3
"""Exhaustively enumerate selected identifiers in a LOCAL pinned IPSW-diff tree.

This is exhaustive for the checked-out public DIFF files, not the entire
original Apple firmware or symbols unchanged between builds.
"""
import argparse
import json
import pathlib
import re

TERMS=["Pumpkin","PumpkinMode","isPumpkin","WnCqFWpQgAFLfacM07K0RA",
       "HomeAccessory","BreadBoard","TestMode2","originIsHomeAccessory",
       "MobileGestalt_get_pumpkinMode"]
PATTERN=re.compile("|".join(sorted(map(re.escape,TERMS),key=len,reverse=True)),re.I)

def scan(root):
    root=pathlib.Path(root)
    if not root.is_dir():raise FileNotFoundError(str(root))
    records=[]
    # Filesystem enumeration differs on Linux and Intel macOS/APFS. Stable
    # sorting is essential for reproducible evidence and unit-test ordering.
    files=sorted(root.rglob("*"), key=lambda p:p.relative_to(root).as_posix())
    checked=0
    for f in files:
        if not f.is_file() or f.suffix not in (".md",".txt",".json",".plist",".strings"):
            continue
        checked+=1
        try:
            lines=f.read_text(encoding="utf-8",errors="replace").splitlines()
        except OSError:continue
        for n,line in enumerate(lines,1):
            matches=list(PATTERN.finditer(line))
            if not matches:continue
            refs=sorted({m.group(0) for m in matches},key=str.casefold)
            category=("potential_identity_reference"
                      if any(x.lower() in line.lower() for x in ("PumpkinMode",
                        "isPumpkin","originIsHomeAccessory",
                        "MobileGestalt_get_pumpkinMode",
                        "WnCqFWpQgAFLfacM07K0RA"))
                      else "homeaccessory_or_breadboard_context"
                      if "homeaccessory" in line.lower() or "breadboard" in line.lower()
                      else "incidental_or_unclassified")
            records.append({"path":str(f.relative_to(root)),"line":n,
               "reference":line[:1500],"tokens":refs,"kind":category,
               "may_be_an_unchanged_reference":False})
    return {
        "version_delta":"iOS 27.2 beta 3 (24B5099f) -> beta 4 (24B5110a)",
        "evidence":"the complete checked-out text DIFF directory only",
        "files_scanned":checked,"matches":len(records),"records":records,
        "mobilegestalt_backing_source_identified":False,
        "homeview_pumpkin_query_observed":False,
        "screenshot_verified":False
    }

def main():
    p=argparse.ArgumentParser()
    p.add_argument("diff_root")
    p.add_argument("--output",default="out/pumpkin-full-diff-inventory.json")
    a=p.parse_args()
    result=scan(a.diff_root)
    out=pathlib.Path(a.output);out.parent.mkdir(parents=True,exist_ok=True)
    out.write_text(json.dumps(result,indent=2)+"\n")
    print(json.dumps({"files_scanned":result["files_scanned"],"matches":result["matches"]}))
    if result["files_scanned"]<500:
        raise SystemExit("Incomplete sparse checkout: under 500 files scanned")
if __name__=="__main__":main()

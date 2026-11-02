#!/usr/bin/env python3
"""Bounded iOS 27.2 Pumpkin cross-reference collector.

Public binary DIFFS are not disassembly and cannot reveal MG getter semantics.
"""
import argparse
import json
import pathlib
import re
import urllib.request

COMMIT="8af66bf3a924930979237d896ee447f0f2684ac8"
ROOT="https://raw.githubusercontent.com/blacktop/ipsw-diffs/"+COMMIT+"/"
D="iOS/27_2_24B5099f_vs_27_2_24B5110a/"
SOURCES={
"MobileGestalt":D+"DYLIBS/usr/lib/libMobileGestalt.dylib.md",
"SiriInformationSearch":D+"DYLIBS/System/Library/PrivateFrameworks/SiriInformationSearch.framework/SiriInformationSearch.md",
"SiriAudioFlow":D+"MACHOS/filesystem/System/Library/Assistant/FlowDelegatePlugins/AudioFlowDelegatePlugin.bundle/AudioFlowDelegatePlugin.md",
"CoreServices":D+"DYLIBS/System/Library/Frameworks/CoreServices.framework/CoreServices.md",
"ProximityControl":D+"MACHOS/filesystem/usr/libexec/proximitycontrold.md",
"WiFiDaemon":D+"MACHOS/filesystem/usr/sbin/wifid.md",
"EligibilityDaemon":D+"MACHOS/filesystem/usr/libexec/eligibilityd.md",
"WirelessProximity":D+"DYLIBS/System/Library/PrivateFrameworks/WPDaemon.framework/WPDaemon.md",
"HomeFeature":D+"FEATURES/filesystem/Domain/Home.plist.md",
"Entitlements":D+"Entitlements.md",
"Restoration":D+"MACHOS/SystemOS/usr/lib/libramrod.dylib.md",
"PegasusEarlier": "iOS/27_0_24A437_vs_27_2_24B5084k/DYLIBS/System/Library/PrivateFrameworks/PegasusAPI.framework/PegasusAPI.md",
"macOS26_7Gestalt": "macOS/26_6_2_25G83_vs_26_7_25G220/DYLIBS/usr/lib/libMobileGestalt.dylib.md",
}
TERMS=("PumpkinMode","MobileGestalt_get_pumpkinMode","isPumpkin","WnCqFWpQgAFLfacM07K0RA",
       "HomeAccessory","BreadBoard","TestMode2","originIsHomeAccessory",
       "DeviceCapabilities","com.apple.private.breadboard")
PATTERN=re.compile("|".join(re.escape(x) for x in TERMS),re.I)
BEHAVIOR={
 "MobileGestalt":"key/symbol exists; backing getter not identified",
 "SiriInformationSearch":"Pegasus capabilities isPumpkin setter, Siri device idiom HomeAccessory; branch truth table unknown",
 "SiriAudioFlow":"originIsHomeAccessory and isPumpkin logged during continuation; true case unproven",
 "CoreServices":"BreadBoard/TestMode2 LaunchServices type string; UI selection unproven",
 "ProximityControl":"HomeAccessory models/assets, BreadBoard app drawer; unrelated to verified Pumpkin derivation",
 "Restoration":"HomeAccessory restore progress; not normal BreadBoard launcher",
}
def extract(name,body):
    path=SOURCES[name]
    result=[]
    for n,line in enumerate(body.splitlines(),1):
        if not PATTERN.search(line):continue
        sign="added" if line.startswith("+") else "removed" if line.startswith("-") else "context"
        result.append({
          "binary_framework":name,"source_path":path,"line":n,"delta":sign,
          "reference":line[:1000],"matched_terms":sorted(set(PATTERN.findall(line)),key=str.lower),
          "behavior_if_pumpkin_true":BEHAVIOR.get(name,"unknown without original instructions"),
          "source_of_property":"unknown; symbols/strings do not prove DeviceTree/NVRAM/PlatformExpert",
          "url":"https://github.com/blacktop/ipsw-diffs/blob/"+COMMIT+"/"+path,
          "runtime_verified":False})
    return result
def download(url):
    with urllib.request.urlopen(url,timeout=40) as response:
        return response.read(2_000_000).decode("utf-8","replace")
def scan(fetch=download):
    records=[];errors=[]
    for name,path in SOURCES.items():
        try:records.extend(extract(name,fetch(ROOT+path)))
        except Exception as error:errors.append({"path":path,"error":str(error)})
    return {"build_from":"24B5099f","build_to":"24B5110a","repo_sha":COMMIT,
            "scope":"selected public diff files, not original binaries",
            "source_count":len(SOURCES),"errors":errors,"references":records,
            "pumpkin_getter_derivation":"unresolved","observed_guest_query":False,
            "observed_guest_return":None,"breadboard_boot_verified":False}
def report(result):
    lines=["# Apple Pumpkin / HomeAccessory xrefs","",
        "Public iOS 27.2 diff: 24B5099f -> 24B5110a.",
        "These are symbol, string, entitlement, feature and Swift API DELTAS, not full firmware disassembly.",
        "","| Binary | Source line | Delta | Reference |","|---|---:|---|---|"]
    for r in result["references"]:
        value=r["reference"].replace("|","&#124;")[:190]
        lines.append("| "+r["binary_framework"]+" | "+str(r["line"])+" | "+r["delta"]+" | "+value+" |")
    lines+=["","## Unresolved",
       "- No Mach-O control-flow trace has established PumpkinMode's backing getter.",
       "- Siri logs name both isPumpkin and originIsHomeAccessory, but not the branch outcome.",
       "- A real Apple DeviceTree property has not been shown to determine PumpkinMode.",
       "- An experimental /chosen/PumpkinMode value does not force MobileGestalt to return true.",
       "- NAND/ANS emulation, DCP/SGX framebuffer, installed HomeView system volume, and native BreadBoard launch remain missing.",
       ""]
    return "\n".join(lines)+"\n"
def main():
    p=argparse.ArgumentParser()
    p.add_argument("--output",default="out/pumpkin-xrefs.json")
    p.add_argument("--markdown",default="out/pumpkin-xrefs.md")
    args=p.parse_args()
    result=scan()
    out=pathlib.Path(args.output);out.parent.mkdir(parents=True,exist_ok=True)
    out.write_text(json.dumps(result,indent=2)+"\n")
    pathlib.Path(args.markdown).write_text(report(result))
    print(json.dumps({"sources":result["source_count"],"matches":len(result["references"]),
                     "source_errors":result["errors"]}))
    if result["errors"]:raise SystemExit(1)
if __name__=="__main__":main()

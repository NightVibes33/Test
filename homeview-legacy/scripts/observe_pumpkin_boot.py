#!/usr/bin/env python3
"""Record observed guest Pumpkin/HomeAccessory behavior from ORIGINAL serial logs.

Never invent MobileGestalt query responses or shell launches. Missing evidence
is reported as unknown, not false. Host-injected DeviceTree hints are separate.
"""
import argparse
import glob
import json
import pathlib
import re

TERMS=("PumpkinMode","isPumpkin","originIsHomeAccessory","HomeAccessory",
       "BreadBoard","CupBoard","SpringBoard","TestMode2","MobileGestalt",
       "Siri","HomeKit","HomeAccessoryService","AppleANS","NAND","framebuffer")
MG_QUERY=re.compile(r"(?:MobileGestalt_get_pumpkinMode|MobileGestalt[^\n]{0,100}PumpkinMode)")
MG_VALUE=re.compile(r"(?:PumpkinMode|pumpkinMode)[^\n]{0,80}?(?:return(?:s|ed)?|value|=|:)[\s]*(true|false|1|0)\b",re.I)
PUMPKIN_BRANCH=re.compile(r"originIsHomeAccessory[^\n]{0,180}isPumpkin",re.I)
SHELL_START=re.compile(r"(?:launchd|running|spawned|starting)[^\n]{0,150}\b(BreadBoard|CupBoard|SpringBoard)\b",re.I)
SERVICE_START=re.compile(r"(?:launchd|running|spawned|starting)[^\n]{0,100}\b(Siri|HomeKit|HomeAccessory)\b",re.I)

def inspect(text):
    mg_queries=[line.strip() for line in text.splitlines() if MG_QUERY.search(line)]
    # Only count return values on guest MobileGestalt query lines, never host-side ADT hints.
    vals=[match.group(1) for line in mg_queries for match in MG_VALUE.finditer(line)]
    branches=[line.strip() for line in text.splitlines() if PUMPKIN_BRANCH.search(line)]
    shells=[m.group(1) for m in SHELL_START.finditer(text)]
    services=[m.group(1) for m in SERVICE_START.finditer(text)]
    refs=[line.strip()[:400] for line in text.splitlines()
          if any(t.lower() in line.lower() for t in TERMS)]
    result={
      "original_apple_guest_serial_examined":True,
      "mg_pumpkinmode_query_observed":bool(mg_queries),
      "mg_pumpkinmode_returned":None,
      "mg_pumpkinmode_return_evidence":False,
      "mg_queries":mg_queries[:40],
      "is_pumpkin_branch_logs":branches[:40],
      "is_pumpkin_branch_executed":bool(branches),
      "apple_homeaccessory_log_mentions":sum("homeaccessory" in r.lower() for r in refs),
      "observed_service_starts":sorted(set(services)),
      "observed_shell_starts":sorted(set(shells)),
      "selected_homeview_shell":shells[-1] if shells else None,
      "device_tree_pumpkin_probe_value_is_not_MG_result":True,
      "hardware_blocker_nand":text.count("Waiting for NAND service to publish"),
      "hardware_blocker_framebuffer":text.count("unable to get framebuffer"),
      "candidate_reference_lines":refs[:120],
      "normal_homeview_ui_verified":False
    }
    if vals:
        parsed=set(v.lower() in ("true","1") for v in vals)
        if len(parsed)==1:
            result["mg_pumpkinmode_returned"]=parsed.pop()
            result["mg_pumpkinmode_return_evidence"]=True
        else:
            result["mg_pumpkinmode_return_conflicting"]=True
    return result

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("--logs",nargs="+",required=True)
    ap.add_argument("--output",required=True)
    args=ap.parse_args()
    inputs=[]
    for pattern in args.logs:
        inputs.extend(glob.glob(pattern))
    results={}
    for path in sorted(set(inputs)):
        if not pathlib.Path(path).is_file():continue
        results[pathlib.Path(path).name]=inspect(pathlib.Path(path).read_text(errors="replace"))
    data={"logs_scanned":len(results),"results":results,
          "runtime_MG_trace_instrumented":False,
          "note":"Serial logs cannot prove MG queries that Apple does not log. An ADT hint is not a guest MG override."}
    output=pathlib.Path(args.output)
    output.parent.mkdir(parents=True,exist_ok=True)
    output.write_text(json.dumps(data,indent=2)+"\n")
    print(json.dumps({"scanned":len(results),
        "queries_seen":sum(v["mg_pumpkinmode_query_observed"] for v in results.values()),
        "returned_values_seen":sum(v["mg_pumpkinmode_return_evidence"] for v in results.values())}))

if __name__=="__main__":main()

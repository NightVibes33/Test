#!/usr/bin/env python3
"""
Regression check for CloudKit JS cross-origin popup-session injection.

Runs the safe isolated PoC and evaluates its metadata-only output.

Exit:
  0 = FIXED (cross-origin synthetic session rejected/not propagated)
  1 = VULNERABLE (cross-origin synthetic session accepted and propagated)
  2 = harness error
"""
from __future__ import annotations
import json
import subprocess
import sys
from pathlib import Path

HERE=Path(__file__).resolve().parent
POC=HERE/"cloudkit_postmessage_poc.py"
RESULT=HERE/"cloudkit-postmessage-poc.json"

def main():
    cp=subprocess.run([sys.executable,str(POC)],cwd=HERE.parent)
    if cp.returncode!=0 or not RESULT.exists():
        print("ERROR: PoC harness failed",file=sys.stderr)
        return 2
    try:
        data=json.loads(RESULT.read_text())
    except Exception as e:
        print(f"ERROR: could not parse result: {e}",file=sys.stderr)
        return 2
    accepted=bool(data.get("accepted_cross_origin_sentinel"))
    propagated=bool(data.get("propagated_cross_origin_sentinel"))
    vulnerable=accepted and propagated
    print("CloudKit JS version:",data.get("pre",{}).get("cloudKitVersion"))
    print("Cross-origin session accepted:",accepted)
    print("Injected session propagated as ckWebAuthToken:",propagated)
    print("REGRESSION STATE:","VULNERABLE" if vulnerable else "FIXED")
    return 1 if vulnerable else 0

if __name__=="__main__":
    raise SystemExit(main())

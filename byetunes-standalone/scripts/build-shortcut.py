#!/usr/bin/env python3
"""Rebuild the original public ByeTunes shortcut as an MP3 Skull workflow."""
import json
import os
import plistlib
import re
import subprocess
import sys
import tempfile
import urllib.request
from pathlib import Path

RECORD="https://www.icloud.com/shortcuts/api/records/49de36f87bf44b21a38056d3c33e41fe"
OLD="com.EduAlexxis.MusicManager"
NEW="com.nightvibes33.mp3skull"
EXPECTED=[
    "is.workflow.actions.vpn.set",
    "is.workflow.actions.file.select",
    OLD+".InjectMusicIntent",
    "is.workflow.actions.vpn.set",
    "is.workflow.actions.returntohomescreen",
]
def read(url):
    request=urllib.request.Request(url,headers={"User-Agent":"MP3Skull-shortcut-build/1.0"})
    with urllib.request.urlopen(request,timeout=40) as response:
        return response.read(1024*1024)
record=json.loads(read(RECORD))
source=record["fields"]["shortcut"]["value"]
url=source["downloadURL"].replace(chr(36)+"{f}","Byetunes.shortcut")
assert url.startswith("https://") and ".icloud-content.com/" in url
raw=read(url)
assert raw.startswith(b"bplist00") and len(raw)==source["size"]
workflow=plistlib.loads(raw)
actions=workflow["WFWorkflowActions"]
assert [a["WFWorkflowActionIdentifier"] for a in actions]==EXPECTED, "Original workflow changed; review before signing"
action=actions[2]
action["WFWorkflowActionIdentifier"]=NEW+".InjectMusicIntent"
params=action["WFWorkflowActionParameters"]
descriptor=params["AppIntentDescriptor"]
assert descriptor["BundleIdentifier"]==OLD
assert descriptor["AppIntentIdentifier"]=="InjectMusicIntent"
descriptor["BundleIdentifier"]=NEW
descriptor["Name"]="MP3 Skull"
# An unsigned IPA has no fixed team. Set the actual signing team optionally;
# do not copy the upstream developer's team into the new shortcut.
team=os.environ.get("MP3_SKULL_TEAM_ID","").strip()
if team:
    assert re.fullmatch(r"[A-Z0-9]{10}",team)
    descriptor["TeamIdentifier"]=team
else:
    descriptor.pop("TeamIdentifier",None)
assert params["audioFiles"]["Value"]["OutputUUID"]==actions[1]["WFWorkflowActionParameters"]["UUID"]
assert actions[1]["WFWorkflowActionParameters"]["SelectMultiple"] is True
assert actions[3]["WFWorkflowActionParameters"]["WFVPNOperation"]=="Disconnect"
workflow["WFWorkflowName"]="MP3 Skull"
data=plistlib.dumps(workflow,fmt=plistlib.FMT_BINARY,sort_keys=False)
assert OLD.encode() not in data
out=Path(sys.argv[1]).resolve()
out.parent.mkdir(parents=True,exist_ok=True)
with tempfile.TemporaryDirectory() as tmp:
    unsigned=Path(tmp)/"MP3 Skull.shortcut"
    unsigned.write_bytes(data)
    signed=Path(tmp)/"MP3 Skull signed.shortcut"
    def valid(path):
        return path.exists() and path.stat().st_size>len(data) and path.read_bytes()[:4]==b"AEA1"
    try:
        subprocess.run(["shortcuts","sign","--mode","anyone","--input",str(unsigned),"--output",str(signed)],check=False,timeout=45)
    except (OSError,subprocess.TimeoutExpired):
        pass
    if not valid(signed):
        print("Local signing unavailable; signing the public static template using HubSign (no user data).")
        subprocess.run(["curl","--fail","--silent","--show-error","--location","--max-time","100","--retry","1","--form","shortcut_name=MP3 Skull","--form","shortcut=@"+str(unsigned),"https://hubsign.routinehub.services/sign","--output",str(signed)],check=True)
    assert valid(signed),"Signing did not return an AEA signed shortcut"
    out.write_bytes(signed.read_bytes())
print("PASS: signed MP3 Skull shortcut; original VPN, file picker, music action, disconnect and Home Screen flow")
print("Team binding:",team or "not pinned; verify on sideloaded device")

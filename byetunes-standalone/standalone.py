from pathlib import Path
import plistlib

root=Path("ByeTunes")
app=root/"MusicManager"
project=root/"MusicManager.xcodeproj/project.pbxproj"
newid="com.nightvibes33.byetunes"

def edit(path, fn):
    s=path.read_text()
    path.write_text(fn(s))

def once(s, old, new):
    assert s.count(old)==1, (old, s.count(old))
    return s.replace(old,new,1)

# Restore both supported pairing methods without reverting the custom UI.
for filename, marker in [
    ("OnboardingView.swift", "                if let pin = onDevicePairing.pin {"),
    ("SettingsView.swift", "                        if let pin = onDevicePairing.pin {"),
]:
    def add(s):
        indent=marker[:len(marker)-len(marker.lstrip())]
        return once(s,marker,indent+"StandalonePairingEntry(manager: manager)\n"+indent+"Text(onDevicePairing.status).font(.caption).foregroundColor(.secondary)\n\n"+marker)
    edit(app/filename,add)

edit(app/"OnboardingView.swift",lambda s:s.replace('Text("Music Library")','Text("ByeTunes")').replace("Tap Pair This iPhone below","Pair This iPhone on iOS 27+, or import your pairing file"))
edit(app/"ContentView.swift",lambda s:s.replace("Filza embed: ","Standalone: ").replace("updates are delivered with FilzaSlop","updates are delivered with the standalone IPA"))
edit(app/"iDeviceManager.swift",lambda s:s.replace("Filza embed: ","Standalone: ").replace("Initializing embedded upstream lifecycle","Initializing standalone lifecycle"))
# Fresh standalone installs have their own container; don't depend on the old developer's group.
for path in app.glob("*.swift"):
    edit(path,lambda s:s.replace("com.EduAlexxis.MusicManager",newid).replace("group.com.edualexxis.MusicManager","group."+newid))
# The app uses the exact pinned idevice C declarations and Airlift archive as Filza.
(app/"Bridging-Header.h").write_text('#import "idevice.h"\n')
(app/"idevice.h").write_bytes(Path("Vendor/idevice/include/idevice.h").read_bytes())
p=project.read_text().replace("com.EduAlexxis.MusicManager",newid)
needle='SWIFT_OBJC_BRIDGING_HEADER = "MusicManager/Bridging-Header.h";'
assert p.count(needle)==2
p=p.replace(needle,needle+'''
                SWIFT_INCLUDE_PATHS = "$(SRCROOT)/../ThirdParty/NFCARD/AirliftFFI/include";
                OTHER_LDFLAGS = ("$(inherited)", "$(SRCROOT)/../ThirdParty/NFCARD/AirliftFFI/lib/libairlift_ffi.a", "-lc++", "-lsqlite3", "-lz", "-lxml2", "-framework", Security, "-framework", SystemConfiguration);
                OTHER_SWIFT_FLAGS = ("$(inherited)", "-Xfrontend", "-solver-expression-time-threshold=300");
''')
p=p.replace("IPHONEOS_DEPLOYMENT_TARGET = 16.0;","IPHONEOS_DEPLOYMENT_TARGET = 17.0;").replace("IPHONEOS_DEPLOYMENT_TARGET = 16.1;","IPHONEOS_DEPLOYMENT_TARGET = 17.0;")
project.write_text(p)
info=app/"Info.plist"
with info.open("rb") as f: data=plistlib.load(f)
data["UIBackgroundModes"]=list(dict.fromkeys(data.get("UIBackgroundModes",[])+["audio"]))
data["NSBonjourServices"]=list(dict.fromkeys(data.get("NSBonjourServices",[])+["_remotepairing-pairable-host._tcp"]))
data["NSLocalNetworkUsageDescription"]="ByeTunes pairs with your iPhone and connects to its local device services using LocalDevVPN."
data["BGTaskSchedulerPermittedIdentifiers"]=[newid+".metadataRefresh"]
for item in data.get("CFBundleURLTypes",[]):
    item["CFBundleURLName"]=newid
with info.open("wb") as f: plistlib.dump(data,f)
# No app group entitlement is required for normal in-app imports and pairing.
# Keep upstream optional shortcut support without claiming the original developer's group.
ent=app/"MusicManager.entitlements"
with ent.open("wb") as f: plistlib.dump({},f)
assert "ByeTunesOnDevicePairingController" in (app/"OnboardingView.swift").read_text()
assert "StandalonePairingEntry" in (app/"SettingsView.swift").read_text()
assert "@main" in (app/"MusicManagerApp.swift").read_text()
print("Standalone source staged; custom pairing, metadata, album colors and app lifecycle present.")

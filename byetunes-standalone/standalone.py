from pathlib import Path
import plistlib

root=Path("ByeTunes")
app=root/"MusicManager"
project=root/"MusicManager.xcodeproj/project.pbxproj"
newid="com.nightvibes33.mp3skull"

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
(app/"idevice.h").write_bytes(Path("Vendor/PairingRuntime/include/idevice.h").read_bytes())
p=project.read_text().replace("com.EduAlexxis.MusicManager",newid)
needle='SWIFT_OBJC_BRIDGING_HEADER = "MusicManager/Bridging-Header.h";'
assert p.count(needle)==2
p=p.replace(needle,needle+'''
                SWIFT_INCLUDE_PATHS = "$(SRCROOT)/../Vendor/PairingRuntime/include";
                OTHER_LDFLAGS = ("$(inherited)", "$(SRCROOT)/../Vendor/PairingRuntime/lib/libairlift_ffi.a", "-lc++", "-lsqlite3", "-lz", "-lxml2", "-framework", Security, "-framework", SystemConfiguration);
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

# MP3 Skull branding; retain upstream Swift symbols, license and dependency paths.
import re, json, subprocess

def rebrand_text(s):
    # A period ending a sentence is not a source-code identifier separator.
    return re.sub(r'(?<![A-Za-z0-9_./-])ByeTunes(?![A-Za-z0-9_/-]|\.[A-Za-z0-9_])','MP3 Skull',s)

assert rebrand_text("Pair with ByeTunes. Approve the request") == "Pair with MP3 Skull. Approve the request"
assert rebrand_text("ByeTunesOnDevicePairingController") == "ByeTunesOnDevicePairingController"
assert rebrand_text("https://github.com/EduAlexxis/ByeTunes.git") == "https://github.com/EduAlexxis/ByeTunes.git"
for folder in [app, root/"MusicManagerLiveActivity", root/"MusicManagerActivityShared"]:
    for path in folder.rglob("*.swift"):
        s=path.read_text()
        s=rebrand_text(s)
        s=s.replace('"byetunes"','"mp3skull"').replace("byetunes://","mp3skull://")
        path.write_text(s)
p=project.read_text().replace("ByeTunes.app","MP3 Skull.app").replace("PRODUCT_NAME = ByeTunes;",'PRODUCT_NAME = "MP3 Skull";').replace("productName = ByeTunes;",'productName = "MP3 Skull";').replace("INFOPLIST_KEY_CFBundleDisplayName = ByeTunes;",'INFOPLIST_KEY_CFBundleDisplayName = "MP3 Skull";')
p=p.replace("path = MP3 Skull.app;", 'path = "MP3 Skull.app";')
p=p.replace("$(BUILT_PRODUCTS_DIR)/MusicManager.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/MusicManager", "$(BUILT_PRODUCTS_DIR)/MP3 Skull.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/MP3 Skull")
assert 'path = "MP3 Skull.app";' in p
project.write_text(p)
subprocess.run(["plutil","-lint",str(project)],check=True)
for scheme in (root/"MusicManager.xcodeproj/xcshareddata/xcschemes").glob("*.xcscheme"):
    edit(scheme,lambda s:s.replace("ByeTunes.app","MP3 Skull.app"))
with info.open("rb") as f: data=plistlib.load(f)
data["CFBundleDisplayName"]="MP3 Skull"
data["CFBundleName"]="MP3 Skull"
data["NSLocalNetworkUsageDescription"]="MP3 Skull uses LocalDevVPN to connect to your iPhone."
for item in data.get("CFBundleURLTypes",[]):
    item["CFBundleURLName"]=newid
    item["CFBundleURLSchemes"]=["mp3skull"]
with info.open("wb") as f: plistlib.dump(data,f)
icon=Path("MP3-Skull-icon.jpg").resolve()
for dirname,images in [
    ("AppIcon.appiconset",[{"filename":"MP3-Skull.png","idiom":"universal","platform":"ios","size":"1024x1024"}]),
    ("AppIconImage.imageset",[{"filename":"MP3-Skull.png","idiom":"universal"}]),
]:
    folder=app/"Assets.xcassets"/dirname
    for old in folder.glob("*.png"): old.unlink()
    subprocess.run(["sips","-s","format","png","-z","1024","1024",str(icon),"--out",str(folder/"MP3-Skull.png")],check=True)
    (folder/"Contents.json").write_text(json.dumps({"images":images,"info":{"author":"xcode","version":1}},indent=2)+"\n")
assert '"MP3 Skull".withCString' in (app/"ByeTunesOnDevicePairing.swift").read_text()
assert "Pair with MP3 Skull" in (app/"StandalonePairingImport.swift").read_text()

assert "Pair with ByeTunes" not in (app/"StandalonePairingImport.swift").read_text()
print("PASS: MP3 Skull pairing label, native app icon and Xcode product configuration")

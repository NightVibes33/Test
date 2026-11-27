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
import re, json, subprocess, sys

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
    subprocess.run([sys.executable,"scripts/clean-icon.py",str(icon),str(folder/"MP3-Skull.png")],check=True)
    (folder/"Contents.json").write_text(json.dumps({"images":images,"info":{"author":"xcode","version":1}},indent=2)+"\n")
assert '"MP3 Skull".withCString' in (app/"ByeTunesOnDevicePairing.swift").read_text()
assert "Pair with MP3 Skull" in (app/"StandalonePairingImport.swift").read_text()

assert "Pair with ByeTunes" not in (app/"StandalonePairingImport.swift").read_text()
print("PASS: MP3 Skull pairing label, native app icon and Xcode product configuration")


# Reference-based backgrounds only; preserve original ByeTunes onboarding,
# its post-connection tutorial, all existing controls, and tab layout.
for filename in ["MusicView.swift","SettingsView.swift","TabViews.swift"]:
    path=app/filename
    text=path.read_text()
    text,n=re.subn(r'Color\(\.systemGroupedBackground\)(\s*\n\s*\.ignoresSafeArea\(\))',r'MP3SkullBackground()\1',text)
    assert n>=1, (filename,"root background missing")
    if filename=="SettingsView.swift":
        text=text.replace(".background(Color(.systemBackground))",".background(MP3SkullTheme.card)")
        assert "Pairing is managed by Filza 27" not in text
    path.write_text(text)

onboarding=app/"OnboardingView.swift"
text=onboarding.read_text()
text,n=re.subn(r'LinearGradient\(\s*gradient: Gradient\(colors: \[Color\(\.systemBackground\), Color\(\.secondarySystemBackground\)\]\),\s*startPoint: \.top,\s*endPoint: \.bottom\s*\)',"MP3SkullBackground()",text,count=1)
assert n==1,"onboarding root gradient missing"
text=text.replace(".fill(Color(.systemBackground))",".fill(MP3SkullTheme.card)")
onboarding.write_text(text)

# Original connection card still leads to the original heartbeat-driven
# completion; manual import and on-device PIN remain available.
assert "if ready {" in text and "isComplete = true" in text
assert "StandalonePairingEntry(manager: manager)" in text
assert "onDevicePairing.start(manager: manager)" in text

edit(app/"MusicManagerApp.swift",lambda s:once(s,"            ContentView()","            ContentView()\n                .preferredColorScheme(.dark)"))
edit(app/"ContentView.swift",lambda s:s.replace(".fill(Color(.systemBackground))\n        )\n        .overlay(\n            Capsule()",".fill(MP3SkullTheme.card)\n        )\n        .overlay(\n            Capsule()"))
print("PASS: reference background applied; original onboarding and connection actions retained")


# Keep decorative full-bleed backgrounds out of the foreground layout's
# size proposal. Native safe areas still govern buttons, labels and lists.
for filename in ("MusicView.swift","SettingsView.swift","TabViews.swift","OnboardingView.swift"):
    path=app/filename
    text=path.read_text()
    text,n=re.subn(r'MP3SkullBackground\(\)\s*\n\s*\.ignoresSafeArea\(\)',"MP3SkullBackdrop()",text)
    assert n>=1,(filename,"background anchor missing")
    path.write_text(text)

# Keep onboarding scrollable even while PIN, status, or accessibility text
# increases the card height. Do not let the status bar/home indicator be
# part of the foreground content region.
path=app/"OnboardingView.swift"
text=path.read_text()
text=once(text,"            VStack(spacing: 0) {\n                Spacer()","            GeometryReader { geometry in\n                ScrollView {\n                    VStack(spacing: 0) {\n                Spacer(minLength: 12)")
text=once(text,"                Spacer().frame(height: 32)\n            }\n        }","                Spacer(minLength: 12)\n                    }\n                    .frame(minHeight: max(0, geometry.size.height - 24))\n                    .padding(.vertical, 12)\n                    .frame(maxWidth: .infinity)\n                }\n                .scrollBounceBehavior(.basedOnSize)\n            }\n        }")
# The original card's top/bottom spacers should not force clipping.
text=text.replace(".padding(.bottom, 36)",".padding(.bottom, 20)")
# On older versions the visible primary action must not launch unsupported
# pairing, but the imported-file path is always available.
text=text.replace(".disabled(isConnecting)\n                .opacity(isConnecting ? 0.65 : 1)",".disabled(isConnecting || ProcessInfo.processInfo.operatingSystemVersion.majorVersion < 27)\n                .opacity(isConnecting ? 0.65 : 1)")
path.write_text(text)

# The original tutorial ignored all safe areas, including its actionable
# controls. Preserve its sequence and gestures while confining content.
path=app/"TutorialOverlayView.swift"
text=path.read_text()
text=once(text,"        .ignoresSafeArea()\n        .animation(", "        .animation(")
text=once(text,"            VStack(spacing: 0) {\n                VStack(spacing: 8) {","            ScrollView {\n            VStack(spacing: 0) {\n                VStack(spacing: 8) {")
text=once(text,"            .padding(.horizontal, 20)\n        }\n    }","            .padding(.horizontal, 20)\n            .padding(.vertical, 12)\n            }\n            .scrollBounceBehavior(.basedOnSize)\n        }\n    }")
# Preserve bottom navigation access without underlapping the home indicator.
text=text.replace(".padding(.bottom, 92)",".padding(.bottom, 72)")
path.write_text(text)

# The shared iCloud shortcut references upstream's bundle and old name.
# Use the installed app's native App Intent instead, never that old link.
path=app/"SettingsView.swift"
text=path.read_text()
text=once(text,'Link(destination: URL(string: "https://www.icloud.com/shortcuts/49de36f87bf44b21a38056d3c33e41fe")!) {','Link(destination: URL(string: "shortcuts://")!) {')
text=once(text,'Text("Add MP3 Skull Shortcut")\n                                    .font(.body)\n                                    .foregroundColor(.primary)','VStack(alignment: .leading, spacing: 4) {\n                                    Text("Add MP3 Skull Shortcut")\n                                        .font(.body)\n                                        .foregroundColor(.primary)\n                                    Text("In Shortcuts, choose MP3 Skull → Add Music to Library.")\n                                        .font(.caption)\n                                        .foregroundColor(.secondary)\n                                }')
# Make status rows fit at narrow sizes and large text settings.
text=text.replace('Text("Refresh")\n                                        .font(.caption.weight(.semibold))','Text("Refresh")\n                                        .font(.caption.weight(.semibold))\n                                        .fixedSize(horizontal: true, vertical: false)')
assert "49de36f87bf44b21a38056d3c33e41fe" not in text
path.write_text(text)
path=app/"MusicManagerIntents.swift"
text=path.read_text()
text=text.replace('static var title: LocalizedStringResource = "Inject Music"','static var title: LocalizedStringResource = "Add Music to Library"')
text=text.replace('shortTitle: "Inject Music"','shortTitle: "Add Music to Library"')
assert 'shortTitle: "Add Music to Library"' in text and r'\(.applicationName)' in text
path.write_text(text)

# Declare custom file extensions as data so document providers can expose
# unknown pairing files as selectable, without claiming ownership of plist.
with info.open("rb") as f: data=plistlib.load(f)
types=data.get("UTImportedTypeDeclarations",[])
types=[x for x in types if x.get("UTTypeIdentifier")!="com.nightvibes33.mp3skull.pairing-record"]
types.append({
    "UTTypeIdentifier":"com.nightvibes33.mp3skull.pairing-record",
    "UTTypeDescription":"Device Pairing Record",
    "UTTypeConformsTo":["public.data"],
    "UTTypeTagSpecification":{"public.filename-extension":["mobiledevicepairing","pairing","rppairing","pairingfile"]}
})
data["UTImportedTypeDeclarations"]=types
with info.open("wb") as f: plistlib.dump(data,f)
assert "DocumentPicker(types: Self.pairingFileTypes" in (app/"StandalonePairingImport.swift").read_text()
print("PASS: pairing document picker, safe-area foreground, native MP3 Skull shortcuts")

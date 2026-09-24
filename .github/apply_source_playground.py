#!/usr/bin/env python3
"""Apply the Swift Playground overlay to the pinned LiveContainer checkout."""
from pathlib import Path
import shutil

root = Path(__file__).resolve().parents[1]
lc = root / "LiveContainer"
ui_root = lc / "LiveContainerSwiftUI"

def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text()
    if new in text:
        return
    if old not in text:
        raise SystemExit(f"Expected upstream marker missing in {path.relative_to(root)}")
    path.write_text(text.replace(old, new, 1))

shared = ui_root / "Utilities/Shared.swift"
text = shared.read_text()
start = text.index("enum LCTabIdentifier: Hashable {")
end = text.index("\n}", start)
block = text[start:end]
if "case playground" not in block:
    if "case settings" not in block:
        raise SystemExit("LCTabIdentifier settings case not found")
    shared.write_text(text[:end] + "\n    case playground" + text[end:])

tabs = ui_root / "Views/LCTabView.swift"
replace_once(tabs,
'''                .tag(LCTabIdentifier.apps)
            if DataManager.shared.model.multiLCStatus != 2 {''',
'''                .tag(LCTabIdentifier.apps)
            SwiftSourcePlaygroundView()
                .tabItem { Label("Swift Playground", systemImage: "curlybraces") }
                .tag(LCTabIdentifier.playground)
            if DataManager.shared.model.multiLCStatus != 2 {''')

source_dir = root / "SwiftSourcePlayground/LiveContainerOverlay"
destination = ui_root / "Views/SourcePlayground"
destination.mkdir(parents=True, exist_ok=True)
for source in source_dir.glob("*.swift"):
    shutil.copy2(source, destination / source.name)

# Compile the same interpreter in LiveContainerSwiftUI; the Swift package above
# remains the host-side test target, while these source files form the iOS UI.
interpreter = root / "SwiftSourcePlayground/Sources/SwiftSourcePlayground/Interpreter.swift"
shutil.copy2(interpreter, destination / interpreter.name)

# Add the SwiftSyntax parser products to the synchronized LiveContainerSwiftUI target.
pbx = lc / "LiveContainer.xcodeproj/project.pbxproj"
text = pbx.read_text()
package_id = "A10000000000000000000001"
product_ids = {"SwiftSyntax":"A10000000000000000000002", "SwiftParser":"A10000000000000000000003", "SwiftParserDiagnostics":"A10000000000000000000004"}
build_ids = {"SwiftSyntax":"B10000000000000000000001", "SwiftParser":"B10000000000000000000002", "SwiftParserDiagnostics":"B10000000000000000000003"}
if package_id not in text:
    build_rows = "\n".join(f"\t\t{build_ids[n]} /* {n} in Frameworks */ = {{isa = PBXBuildFile; productRef = {product_ids[n]} /* {n} */; }};" for n in product_ids) + "\n"
    marker = "/* End PBXBuildFile section */"
    if marker not in text: raise SystemExit("PBXBuildFile section marker missing")
    text = text.replace(marker, build_rows + marker, 1)
    target_id = "17413FB42D9C0BAE00F3F928"
    target_start = text.index(f"{target_id} /* LiveContainerSwiftUI */ = {{")
    target_end = text.index("\n\t\t};", target_start)
    target = text[target_start:target_end]
    target_marker = "packageProductDependencies = (\n\t\t\t);"
    if target_marker not in target: raise SystemExit("LiveContainerSwiftUI package dependency list missing")
    rows = "\n".join(f"\t\t\t\t{product_ids[n]} /* {n} */," for n in product_ids)
    target = target.replace(target_marker, f"packageProductDependencies = (\n{rows}\n\t\t\t);", 1)
    text = text[:target_start] + target + text[target_end:]
    phase_id = "17413FB22D9C0BAE00F3F928"
    phase_start = text.index(f"{phase_id} /* Frameworks */ = {{")
    phase_end = text.index("\n\t\t};", phase_start)
    phase = text[phase_start:phase_end]
    phase_marker = "\t\t\t\t174140D62D9C176F00F3F928 /* libarchive.tbd in Frameworks */,"
    if phase_marker not in phase: raise SystemExit("LiveContainerSwiftUI framework marker missing")
    rows = "\n".join(f"\t\t\t\t{build_ids[n]} /* {n} in Frameworks */," for n in product_ids)
    phase = phase.replace(phase_marker, phase_marker + "\n" + rows, 1)
    text = text[:phase_start] + phase + text[phase_end:]
    project_marker = "packageReferences = (\n\t\t\t);"
    if project_marker not in text: raise SystemExit("PBXProject packageReferences list missing")
    package_ref = f'\t\t\t\t{package_id} /* XCRemoteSwiftPackageReference "swift-syntax" */,'
    text = text.replace(project_marker, f"packageReferences = (\n{package_ref}\n\t\t\t);", 1)
    sections = (
      "/* Begin XCRemoteSwiftPackageReference section */\n"
      f'\t\t{package_id} /* XCRemoteSwiftPackageReference "swift-syntax" */ = {{isa = XCRemoteSwiftPackageReference; repositoryURL = "https://github.com/swiftlang/swift-syntax.git"; requirement = {{kind = exactVersion; version = 603.0.1; }}; }};\n'
      "/* End XCRemoteSwiftPackageReference section */\n"
      "/* Begin XCSwiftPackageProductDependency section */\n"
      + "\n".join(f'\t\t{product_ids[n]} /* {n} */ = {{isa = XCSwiftPackageProductDependency; package = {package_id} /* XCRemoteSwiftPackageReference "swift-syntax" */; productName = {n}; }};' for n in product_ids)
      + "\n/* End XCSwiftPackageProductDependency section */\n"
    )
    final_marker = "\n\t};\n\trootObject ="
    if final_marker not in text: raise SystemExit("PBX objects dictionary end marker missing")
    text = text.replace(final_marker, "\n" + sections + final_marker, 1)
    pbx.write_text(text)
print("Applied Swift Playground overlay to LiveContainer.")

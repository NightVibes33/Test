import SwiftUI

/// Read-only index from the user-provided Cinder27 v2.0 archive.
/// These are candidate tests, not verified exploitation results.
private struct CinderRecord: Identifiable {
    let id: String
    let module: String
    let component: String
    let primitive: String
}

private enum CinderInventory {
    static let raw = """
    CVE-2026-112415|vid.hevc|Video decoder|Out-of-bounds read
    CVE-2026-112416|vid.avc|Video decoder|Out-of-bounds write
    CVE-2026-112485|mdl.usda|Model I/O|Out-of-bounds read
    CVE-2026-112488|iio.tiff.direntry|ImageIO|Out-of-bounds write
    CVE-2026-112507|kern.ipc|XNU IPC|Use-after-free
    CVE-2026-112515|probe.hid|IOHIDFamily|Out-of-bounds read
    CVE-2026-112522|arc.iso|libarchive|Out-of-bounds write
    CVE-2026-112546|aud.hoa|AudioCodecs|Out-of-bounds read
    CVE-2026-112554|kext.gpt|IOStorageFamily|Out-of-bounds read
    CVE-2026-112571|iio.jpeg.comment|ImageIO|Information disclosure
    CVE-2026-112610|cg.cmap|CoreGraphics|Negative-result probe
    CVE-2026-112611|cg.shading|CoreGraphics|Out-of-bounds write
    CVE-2026-112619|cal.unzip|CalendarFoundation|Out-of-bounds write
    CVE-2026-112625|iio.ktx2|ImageIO|Integer overflow
    CVE-2026-112627|iio.dds.bc7|ImageIO|Out-of-bounds read
    CVE-2026-112629|iio.jpeg.gps|ImageIO|Out-of-bounds read
    CVE-2026-112630|iio.apng.fctl|ImageIO|Information disclosure
    CVE-2026-112632|iio.tiff.trunc|ImageIO|Information disclosure
    CVE-2026-112633|iio.tiff.planar|ImageIO|Out-of-bounds write
    CVE-2026-112634|iio.jpeg.marker|ImageIO|Out-of-bounds read
    CVE-2026-112638|aud.lc3|AudioCodecs|Out-of-bounds write
    CVE-2026-112646|sb.stash|SpringBoard|Out-of-bounds write
    CVE-2026-112656|font.gdef|CoreText|Out-of-bounds read
    CVE-2026-112683|font.cff|FontParser|Out-of-bounds write
    CVE-2026-112688|cm.rpu|CoreMedia|Out-of-bounds write
    CVE-2026-112696|probe.ane|Apple Neural Engine|Kernel reachability probe
    CVE-2026-112706|cm.fdleak|CoreMedia|Information disclosure
    CVE-2026-113907|aud.haptic|AudioToolbox|Out-of-bounds write
    CVE-2026-113910|kern.decmpfs|XNU filesystem|Information disclosure
    CVE-2026-113912|aud.drc|AudioCodecs|Out-of-bounds read
    CVE-2026-65385|kext.iohid|IOKit|Out-of-bounds write
    arc.rr|arc.rr|libarchive|RockRidge relocation-cycle probe (no CVE)
    """
    static let entries: [CinderRecord] = raw.split(separator: "\n").compactMap { line in
        let fields = line.trimmingCharacters(in: .whitespaces).split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard fields.count == 4 else { return nil }
        return CinderRecord(id: fields[0], module: fields[1], component: fields[2], primitive: fields[3])
    }
}

struct Cinder27POCIndexView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var filter = ""

    private var matches: [CinderRecord] {
        let q = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return CinderInventory.entries }
        return CinderInventory.entries.filter {
            [$0.id, $0.module, $0.component, $0.primitive]
                .contains { $0.localizedCaseInsensitiveContains(q) }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("32 source inventory entries: 31 CVE-labelled families and one separate RockRidge probe. These entries have not been executed or validated on this device.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("PoC inventory") {
                    ForEach(matches) { record in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(record.id).font(.headline.monospaced())
                            Text(record.module).font(.subheadline)
                            Text(record.component + " · " + record.primitive)
                                .font(.caption).foregroundStyle(.secondary)
                            Text("Status: not tested on this device")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .searchable(text: $filter)
            .navigationTitle("Cinder27 inventory")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

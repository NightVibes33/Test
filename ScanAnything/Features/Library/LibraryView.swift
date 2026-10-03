import SwiftUI

struct LibraryView: View {
    @Environment(ScanStorage.self) private var storage

    /// Hand-rolled rather than using `List(selection:)` plus `EditButton`.
    ///
    /// Two reasons, both found the hard way. A `selection` binding on `List` takes
    /// over row taps, so `NavigationLink` rows stop navigating and just highlight.
    /// And `EditButton` writes to the ambient `editMode` environment value, which a
    /// local `.environment(\.editMode, …)` override on the list silently
    /// disconnects — the button toggles one value while the list reads another.
    ///
    /// Owning the mode means a tap does exactly one thing, chosen here.
    @State private var isSelecting = false
    @State private var selection = Set<UUID>()
    @State private var isConfirmingBulkDelete = false
    @State private var selectedFilter: LibraryFilter = .all

    private var filteredScans: [ScanRecord] {
        storage.scans.filter { selectedFilter.includes($0) }
    }

    var body: some View {
        Group {
            if storage.scans.isEmpty {
                ContentUnavailableView(
                    "No scans yet",
                    systemImage: "square.stack.3d.up.slash",
                    description: Text("Create your first scan from the Scan tab.")
                )
            } else {
                List {
                    Section {
                        filterBar
                            .listRowInsets(
                                EdgeInsets(
                                    top: 8,
                                    leading: 0,
                                    bottom: 8,
                                    trailing: 0
                                )
                            )
                    }

                    if filteredScans.isEmpty {
                        ContentUnavailableView(
                            "No \(selectedFilter.title.lowercased()) scans",
                            systemImage: selectedFilter.symbolName,
                            description: Text("Choose another category or create a new scan.")
                        )
                    } else {
                        ForEach(filteredScans) { record in
                            row(for: record)
                        }
                        .onDelete { offsets in
                            delete(
                                filteredScans.enumerated()
                                    .filter { offsets.contains($0.offset) }
                                    .map(\.element)
                            )
                        }
                    }
                }
            }
        }
        // Doubles as confirmation that tapping a row actually registered.
        .navigationTitle(selectionTitle)
        .navigationDestination(for: UUID.self) { ScanDetailView(recordID: $0) }
        .toolbar {
            if !storage.scans.isEmpty {
                if isSelecting {
                    ToolbarItem(placement: .topBarLeading) { selectAllButton }
                    // Not `.bottomBar`: this screen lives inside a TabView, whose tab
                    // bar owns the bottom edge, and the item simply never drew there.
                    ToolbarItem(placement: .topBarTrailing) { deleteSelectedButton }
                }
                ToolbarItem(placement: .topBarTrailing) { selectModeButton }
            }
        }
        .confirmationDialog(
            "Delete \(selection.count) scans?",
            isPresented: $isConfirmingBulkDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { deleteSelected() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Models and source images will be permanently deleted. This cannot be undone.")
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private func row(for record: ScanRecord) -> some View {
        let content = ScanRow(record: record, modelURL: storage.modelURL(for: record))

        if isSelecting {
            Button {
                if selection.contains(record.id) {
                    selection.remove(record.id)
                } else {
                    selection.insert(record.id)
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: selection.contains(record.id) ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(selection.contains(record.id) ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                    content
                }
                .contentShape(.rect)
            }
            // Plain, or the whole row would render in the accent colour.
            .buttonStyle(.plain)
        } else {
            // Navigate by id, not by value: the detail screen renames records, and a
            // captured copy would go stale immediately.
            NavigationLink(value: record.id) { content }
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(LibraryFilter.allCases) { filter in
                    Button {
                        selectedFilter = filter
                        selection.removeAll()
                    } label: {
                        Label(filter.title, systemImage: filter.symbolName)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                selectedFilter == filter
                                    ? Color.accentColor.opacity(0.18)
                                    : Color.secondary.opacity(0.10),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Toolbar

    private var selectionTitle: String {
        guard isSelecting else { return "Library" }
        return selection.isEmpty ? String(localized: "Select") : "\(selection.count) selected"
    }

    private var selectModeButton: some View {
        Button(isSelecting ? "Done" : "Select") {
            isSelecting.toggle()
            // Ticks left behind would silently apply to the next round of selecting.
            if !isSelecting { selection.removeAll() }
        }
    }

    private var selectAllButton: some View {
        let visibleIDs = Set(filteredScans.map(\.id))
        let allVisibleSelected =
            !visibleIDs.isEmpty &&
            visibleIDs.isSubset(of: selection)

        return Button(allVisibleSelected ? "Deselect All" : "Select All") {
            if allVisibleSelected {
                selection.subtract(visibleIDs)
            } else {
                selection.formUnion(visibleIDs)
            }
        }
    }

    private var deleteSelectedButton: some View {
        Button {
            isConfirmingBulkDelete = true
        } label: {
            Label("Delete", systemImage: "trash")
        }
        // Red rather than the accent colour, so it reads as destructive even though
        // it now sits in the navigation bar next to a harmless "Done".
        .tint(.red)
        .disabled(selection.isEmpty)
    }

    // MARK: - Actions

    private func deleteSelected() {
        // Resolved to records before deleting: `storage.scans` shrinks as it goes,
        // so anything holding indices would delete the wrong rows.
        delete(storage.scans.filter { selection.contains($0.id) })
        selection.removeAll()
        isSelecting = false
    }

    private func delete(_ records: [ScanRecord]) {
        for record in records {
            // The thumbnail is cached by URL, and a new scan can reuse a path.
            let modelURL = storage.modelURL(for: record)
            ThumbnailStore.shared.invalidate(modelURL)
            ThumbnailStore.shared.invalidate(
                modelURL.deletingLastPathComponent()
                    .appending(path: "hero.png", directoryHint: .notDirectory)
            )
            storage.delete(record)
        }
    }
}

private enum LibraryFilter: String, CaseIterable, Identifiable {
    case all
    case object
    case room
    case product
    case freeform

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .object: "Objects"
        case .room: "Rooms"
        case .product: "Products"
        case .freeform: "Freeform"
        }
    }

    var symbolName: String {
        switch self {
        case .all: "square.grid.2x2"
        case .object: "cube.transparent"
        case .room: "house"
        case .product: "shippingbox"
        case .freeform: "viewfinder"
        }
    }

    func includes(_ record: ScanRecord) -> Bool {
        switch self {
        case .all:
            true
        case .object:
            record.assetKind == .object
        case .room:
            record.assetKind == .room
        case .product:
            record.assetKind == .product
        case .freeform:
            record.assetKind == .freeform
        }
    }
}

private struct ScanRow: View {
    let record: ScanRecord
    let modelURL: URL

    var body: some View {
        HStack(spacing: 12) {
            let heroURL = modelURL
                .deletingLastPathComponent()
                .appending(path: "hero.png", directoryHint: .notDirectory)

            if FileManager.default.fileExists(
                atPath: heroURL.path(percentEncoded: false)
            ) {
                ModelThumbnailView(url: heroURL, side: 54)
            } else if record.isPreviewable {
                ModelThumbnailView(url: modelURL, side: 68)
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(.quaternary)
                    .frame(width: 68, height: 68)
                    .overlay {
                        Image(systemName: record.isGaussianSplat ? "sparkles.rectangle.stack" : "aqi.medium")
                            .foregroundStyle(.secondary)
                    }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(record.name)
                    .font(.body)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Label(
                        record.assetKind?.displayName ?? record.engine.displayName,
                        systemImage: record.assetKind?.symbolName ?? record.engine.symbolName
                    )
                    if let summary = record.summary,
                       summary != record.assetKind?.displayName {
                        Text("·")
                        Text(summary)
                    }
                    if let count = record.imageCount {
                        Text("·")
                        Text("\(count) images")
                    }
                    if let count = record.pointCount {
                        Text("·")
                        Text("\(count) points")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

                Text(record.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Detail

struct ScanDetailView: View {
    let recordID: UUID

    @Environment(ScanStorage.self) private var storage

    @State private var exportFormat: MeshExportFormat = .usdz
    @State private var shareableURL: URL?
    @State private var isExporting = false
    @State private var isBundling = false
    @State private var errorMessage: String?
    @State private var draftName = ""

    private var record: ScanRecord? {
        storage.scans.first { $0.id == recordID }
    }

    var body: some View {
        if let record {
            detail(for: record)
        } else {
            // Reachable if the scan is deleted while this screen is on-screen.
            ContentUnavailableView("Scan not found", systemImage: "questionmark.folder")
        }
    }

    private func detail(for record: ScanRecord) -> some View {
        List {
            if record.isGaussianSplat {
                Section {
                    GaussianSplatView(url: storage.modelURL(for: record))
                        .frame(height: 360)
                        .listRowInsets(EdgeInsets())
                } footer: {
                    Text("Interactive 3D model rendered directly on this device.")
                }
            } else if record.isPreviewable {
                Section {
                    ModelPreviewView(url: storage.modelURL(for: record))
                        .frame(height: 320)
                        .listRowInsets(EdgeInsets())
                }
            } else {
                Section {
                    PointCloudPreviewView(url: storage.modelURL(for: record))
                        .frame(height: 320)
                        .listRowInsets(EdgeInsets())
                } footer: {
                    Text("Drag to rotate and pinch to zoom.")
                }
            }

            Section("Info") {
                TextField("Name", text: $draftName)
                    .onSubmit { storage.rename(record, to: draftName) }
                LabeledContent(
                    "Type",
                    value: record.assetKind?.displayName ?? record.engine.displayName
                )
                if let summary = record.summary {
                    LabeledContent("Contents", value: summary)
                }
                if let detail = record.detail {
                    LabeledContent("Detail", value: detail.displayName)
                }
                LabeledContent("Scale", value: record.isMetricallyScaled ? String(localized: "Real size") : String(localized: "Unscaled"))
                LabeledContent("Date", value: record.createdAt.formatted(date: .abbreviated, time: .shortened))
                if let count = record.imageCount {
                    LabeledContent("Images", value: "\(count)")
                }
                if let count = record.pointCount {
                    LabeledContent("Points", value: "\(count)")
                }
                if let dimensions = record.dimensionsMillimetres, dimensions.count == 3 {
                    LabeledContent(
                        "Dimensions",
                        value: "\(dimensions[0]) × \(dimensions[1]) × \(dimensions[2]) mm"
                    )
                }
            }

            exportSection(for: record)

            if storage.hasIntermediates(for: record) {
                fullDetailSection(for: record)
            }
        }
        .navigationTitle(record.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let shareableURL {
                    ShareLink(item: shareableURL)
                }
            }
        }
        .alert(
            "Operation failed",
            isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
        ) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .onAppear { draftName = record.name }
    }

    // MARK: - Sections

    @ViewBuilder
    private func exportSection(for record: ScanRecord) -> some View {
        if record.isGaussianSplat {
            gaussianExportSection(for: record)
        } else if record.isPreviewable {
            meshExportSection(for: record)
        } else {
            Section {
                Button("Share PLY") { sharePointCloud(record) }
            } header: {
                Text("Export")
            } footer: {
                Text("The point cloud is saved as PLY.")
            }
        }
    }

    private func gaussianExportSection(for record: ScanRecord) -> some View {
        let modelURL = storage.modelURL(for: record)
        let folder = modelURL.deletingLastPathComponent()
        let plyURL = folder.appending(path: "model.ply", directoryHint: .notDirectory)
        let heroURL = folder.appending(path: "hero.png", directoryHint: .notDirectory)

        return Section {
            Button {
                shareableURL = modelURL
            } label: {
                Label("Share SPZ", systemImage: "cube.transparent")
            }

            Button {
                if FileManager.default.fileExists(atPath: plyURL.path(percentEncoded: false)) {
                    shareableURL = plyURL
                } else {
                    exportGaussianPLY(source: modelURL, destination: plyURL)
                }
            } label: {
                HStack {
                    Label(
                        FileManager.default.fileExists(atPath: plyURL.path(percentEncoded: false))
                            ? "Share Gaussian PLY"
                            : "Export Gaussian PLY",
                        systemImage: "point.3.connected.trianglepath.dotted"
                    )
                    if isExporting {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(isExporting)

            if FileManager.default.fileExists(atPath: heroURL.path(percentEncoded: false)) {
                Button {
                    shareableURL = heroURL
                } label: {
                    Label("Share Isolated PNG", systemImage: "photo")
                }
            }
        } header: {
            Text("Export")
        } footer: {
            Text("SPZ is the compact 3D Gaussian model. PLY is a broader Gaussian-splat interchange format. The PNG is an on-device foreground-isolated still when Vision could identify the object.")
        }
    }

    private func meshExportSection(for record: ScanRecord) -> some View {
        Section {
            Picker("Format", selection: $exportFormat) {
                ForEach(MeshExportFormat.allCases) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.segmented)

            Text(exportFormat.explanation)
                .font(.footnote)
                .foregroundStyle(.secondary)

            if exportFormat.isGeometryOnly {
                Label("This format does not include materials or textures — geometry only.", systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Button {
                export(record)
            } label: {
                HStack {
                    Text("Export")
                    if isExporting {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(isExporting)
        } header: {
            Text("Export")
        } footer: {
            Text("The prepared file appears in the Share button at the top right.")
        }
    }

    private func fullDetailSection(for record: ScanRecord) -> some View {
        Section {
            LabeledContent(
                "Source images",
                value: ByteCountFormatter.string(
                    fromByteCount: storage.intermediateBytes(for: record),
                    countStyle: .file
                )
            )

            Button {
                bundleImages(record)
            } label: {
                HStack {
                    Text("Export Images to Mac (.zip)")
                    if isBundling {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(isBundling)

            DisclosureGroup("What should I do on a Mac?") {
                Text(SourceImageBundle.macInstructions)
                    .font(.footnote.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Button("Delete Source Images", role: .destructive) {
                storage.purgeIntermediates(for: record)
            }
        } header: {
            Text("Full detail")
        } footer: {
            Text("The on-device model uses the `reduced` level. Reprocessing the same images on a Mac with `detail: .full` or `.raw` can produce a much higher-polygon mesh. Deleting the source images removes that option.")
        }
    }

    // MARK: - Actions

    private func export(_ record: ScanRecord) {
        isExporting = true
        shareableURL = nil
        Task {
            do {
                shareableURL = try await MeshExporter.export(
                    modelAt: storage.modelURL(for: record),
                    as: exportFormat,
                    namedLike: record.name
                )
            } catch {
                errorMessage = error.localizedDescription
            }
            isExporting = false
        }
    }

    private func sharePointCloud(_ record: ScanRecord) {
        shareableURL = storage.modelURL(for: record)
    }

    private func exportGaussianPLY(source: URL, destination: URL) {
        isExporting = true
        shareableURL = nil

        Task {
            do {
                shareableURL = try await GaussianExportService.exportPLY(
                    from: source,
                    to: destination
                )
            } catch {
                errorMessage = error.localizedDescription
            }
            isExporting = false
        }
    }

    private func bundleImages(_ record: ScanRecord) {
        isBundling = true
        shareableURL = nil
        Task {
            do {
                shareableURL = try await SourceImageBundle.makeArchive(
                    imagesDirectory: storage.directoryURL(for: record).appending(path: "images"),
                    named: record.name
                )
            } catch {
                errorMessage = error.localizedDescription
            }
            isBundling = false
        }
    }
}

#Preview {
    NavigationStack { LibraryView() }
        .environment(ScanStorage())
        .preferredColorScheme(.dark)
}

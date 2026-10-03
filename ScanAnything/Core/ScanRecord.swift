import Foundation

struct ScanRecord: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var name: String
    let createdAt: Date
    let engine: ScanEngineKind
    let modelFileName: String
    let isMetricallyScaled: Bool
    let imageCount: Int?
    var pointCount: Int?
    var dimensionsMillimetres: [Int]?
    let detail: ReconstructionDetail?
    var summary: String?

    var isGaussianSplat: Bool {
        let name = modelFileName.lowercased()
        return name.hasSuffix(".spz") || name.hasSuffix(".splat")
    }

    var isPreviewable: Bool {
        modelFileName.lowercased().hasSuffix(".usdz")
    }

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        engine: ScanEngineKind,
        modelFileName: String = "model.usdz",
        isMetricallyScaled: Bool,
        imageCount: Int? = nil,
        pointCount: Int? = nil,
        dimensionsMillimetres: [Int]? = nil,
        detail: ReconstructionDetail? = nil,
        summary: String? = nil
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.engine = engine
        self.modelFileName = modelFileName
        self.isMetricallyScaled = isMetricallyScaled
        self.imageCount = imageCount
        self.pointCount = pointCount
        self.dimensionsMillimetres = dimensionsMillimetres
        self.detail = detail
        self.summary = summary
    }
}

enum ReconstructionDetail: String, Codable, CaseIterable, Sendable, Identifiable {
    case reduced

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .reduced: "On-device (reduced)"
        }
    }

    var explanation: String {
        switch self {
        case .reduced:
            "iOS supports reduced-detail on-device photogrammetry. Source images can be reprocessed on macOS at higher detail."
        }
    }
}

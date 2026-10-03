import Foundation

struct ScanRecord: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var name: String
    let createdAt: Date
    let engine: ScanEngineKind
    let assetKind: ScanAssetKind?
    let modelFileName: String
    let isMetricallyScaled: Bool
    let imageCount: Int?
    var pointCount: Int?
    var dimensionsMillimetres: [Int]?
    let detail: ReconstructionDetail?
    var summary: String?

    var isGaussianSplat: Bool {
        let name = modelFileName.lowercased()
        return name.hasSuffix(".ply") ||
            name.hasSuffix(".spz") ||
            name.hasSuffix(".splat")
    }

    var isPreviewable: Bool {
        modelFileName.lowercased().hasSuffix(".usdz")
    }

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        engine: ScanEngineKind,
        assetKind: ScanAssetKind? = nil,
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
        self.assetKind = assetKind
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


enum ScanAssetKind: String, Codable, Sendable, Hashable {
    case object
    case room
    case product
    case freeform

    var displayName: String {
        switch self {
        case .object: "Object"
        case .room: "Room"
        case .product: "Product"
        case .freeform: "Freeform"
        }
    }

    var symbolName: String {
        switch self {
        case .object: "cube.transparent"
        case .room: "house"
        case .product: "arrow.trianglehead.2.clockwise.rotate.90"
        case .freeform: "viewfinder"
        }
    }
}

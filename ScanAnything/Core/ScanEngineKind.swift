import Foundation

enum ScanEngineKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case objectCapture
    case turntable
    case trueDepth
    case roomPlan

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .objectCapture: "Object"
        case .turntable: "Turntable"
        case .trueDepth: "TrueDepth"
        case .roomPlan: "Room"
        }
    }

    var tagline: String {
        switch self {
        case .objectCapture: "Rear camera • guided 3D capture"
        case .turntable: "Fixed camera • rotating object"
        case .trueDepth: "Front depth sensor • close-range geometry"
        case .roomPlan: "LiDAR • walls, doors and furniture"
        }
    }

    var symbolName: String {
        switch self {
        case .objectCapture: "camera.viewfinder"
        case .turntable: "arrow.trianglehead.clockwise.rotate.90"
        case .trueDepth: "faceid"
        case .roomPlan: "house"
        }
    }

    var isImplemented: Bool { true }

    var producesMesh: Bool {
        switch self {
        case .objectCapture, .turntable, .roomPlan: true
        case .trueDepth: false
        }
    }

    var maturity: Maturity {
        switch self {
        case .objectCapture, .roomPlan: .stable
        case .turntable, .trueDepth: .beta
        }
    }

    enum Maturity: Sendable {
        case stable
        case beta

        var badge: String? {
            switch self {
            case .stable: nil
            case .beta: "beta"
            }
        }
    }
}

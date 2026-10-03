import Foundation
import simd

struct CameraOnlyFrame: Sendable {
    let fileName: String
    let cameraToWorld: [Float]
    let intrinsics: [Float]
    let width: Int
    let height: Int
}

struct CameraOnlyRecorderSnapshot: Sendable {
    let frames: [CameraOnlyFrame]
    let featurePoints: [SIMD3<Float>]
}

enum CameraOnlyDatasetWriter {
    enum DatasetError: LocalizedError {
        case notEnoughFrames(Int)
        case notEnoughPoints(Int)

        var errorDescription: String? {
            switch self {
            case .notEnoughFrames(let count):
                "Not enough camera views were captured (\(count)). Capture at least 24 views."
            case .notEnoughPoints(let count):
                "Not enough AR feature points were captured (\(count)). Scan in brighter light around a textured background."
            }
        }
    }

    static func write(_ snapshot: CameraOnlyRecorderSnapshot, at root: URL) throws {
        guard snapshot.frames.count >= 24 else {
            throw DatasetError.notEnoughFrames(snapshot.frames.count)
        }
        guard snapshot.featurePoints.count >= 100 else {
            throw DatasetError.notEnoughPoints(snapshot.featurePoints.count)
        }

        let sparse = root.appending(path: "sparse/0", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: sparse, withIntermediateDirectories: true)

        var cameras = "# Camera list\n"
        var images = "# Image list\n"
        for (offset, frame) in snapshot.frames.enumerated() {
            let cameraID = offset + 1
            let imageID = offset + 1
            let intrinsics = frame.intrinsics
            guard intrinsics.count == 9, frame.cameraToWorld.count == 16 else { continue }

            let fx = intrinsics[0]
            let fy = intrinsics[4]
            let cx = intrinsics[6]
            let cy = intrinsics[7]
            cameras += "\(cameraID) PINHOLE \(frame.width) \(frame.height) \(fx) \(fy) \(cx) \(cy)\n"

            let pose = colmapPose(from: matrix4x4(frame.cameraToWorld))
            images += "\(imageID) \(pose.qw) \(pose.qx) \(pose.qy) \(pose.qz) \(pose.tx) \(pose.ty) \(pose.tz) \(cameraID) \(frame.fileName)\n\n"
        }

        var points = "# 3D point list\n"
        for (offset, point) in snapshot.featurePoints.enumerated() {
            points += "\(offset + 1) \(point.x) \(point.y) \(point.z) 190 190 190 0\n"
        }

        try cameras.write(to: sparse.appending(path: "cameras.txt"), atomically: true, encoding: .utf8)
        try images.write(to: sparse.appending(path: "images.txt"), atomically: true, encoding: .utf8)
        try points.write(to: sparse.appending(path: "points3D.txt"), atomically: true, encoding: .utf8)
    }

    private static func matrix4x4(_ values: [Float]) -> simd_float4x4 {
        simd_float4x4(columns: (
            SIMD4(values[0], values[1], values[2], values[3]),
            SIMD4(values[4], values[5], values[6], values[7]),
            SIMD4(values[8], values[9], values[10], values[11]),
            SIMD4(values[12], values[13], values[14], values[15])
        ))
    }

    private static func colmapPose(from cameraToWorld: simd_float4x4) -> (
        qw: Float, qx: Float, qy: Float, qz: Float,
        tx: Float, ty: Float, tz: Float
    ) {
        let flip = simd_float4x4(columns: (
            SIMD4<Float>(1, 0, 0, 0),
            SIMD4<Float>(0, -1, 0, 0),
            SIMD4<Float>(0, 0, -1, 0),
            SIMD4<Float>(0, 0, 0, 1)
        ))
        let worldToCamera = flip * simd_inverse(cameraToWorld)
        let rotation = simd_float3x3(columns: (
            SIMD3(worldToCamera.columns.0.x, worldToCamera.columns.0.y, worldToCamera.columns.0.z),
            SIMD3(worldToCamera.columns.1.x, worldToCamera.columns.1.y, worldToCamera.columns.1.z),
            SIMD3(worldToCamera.columns.2.x, worldToCamera.columns.2.y, worldToCamera.columns.2.z)
        ))
        let q = quaternion(from: rotation)
        let t = worldToCamera.columns.3
        return (q.w, q.x, q.y, q.z, t.x, t.y, t.z)
    }

    private static func quaternion(from m: simd_float3x3) -> SIMD4<Float> {
        let r00 = m.columns.0.x, r01 = m.columns.1.x, r02 = m.columns.2.x
        let r10 = m.columns.0.y, r11 = m.columns.1.y, r12 = m.columns.2.y
        let r20 = m.columns.0.z, r21 = m.columns.1.z, r22 = m.columns.2.z
        let trace = r00 + r11 + r22

        var w: Float
        var x: Float
        var y: Float
        var z: Float

        if trace > 0 {
            let s = sqrt(trace + 1) * 2
            w = 0.25 * s
            x = (r21 - r12) / s
            y = (r02 - r20) / s
            z = (r10 - r01) / s
        } else if r00 > r11 && r00 > r22 {
            let s = sqrt(1 + r00 - r11 - r22) * 2
            w = (r21 - r12) / s
            x = 0.25 * s
            y = (r01 + r10) / s
            z = (r02 + r20) / s
        } else if r11 > r22 {
            let s = sqrt(1 + r11 - r00 - r22) * 2
            w = (r02 - r20) / s
            x = (r01 + r10) / s
            y = 0.25 * s
            z = (r12 + r21) / s
        } else {
            let s = sqrt(1 + r22 - r00 - r11) * 2
            w = (r10 - r01) / s
            x = (r02 + r20) / s
            y = (r12 + r21) / s
            z = 0.25 * s
        }

        let length = sqrt(w * w + x * x + y * y + z * z)
        return SIMD4(w / length, x / length, y / length, z / length)
    }
}

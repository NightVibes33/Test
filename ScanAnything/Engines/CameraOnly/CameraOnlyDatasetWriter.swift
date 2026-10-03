import Foundation
import simd

enum CameraOnlyDatasetWriter {
    static func write(
        snapshot: CameraOnlyCaptureSnapshot,
        to root: URL
    ) throws {
        guard !snapshot.frames.isEmpty else {
            throw ScanEngineError.noImagesCaptured
        }
        guard snapshot.featurePoints.count >= 100 else {
            throw ScanEngineError.reconstructionFailed(
                "ARKit did not collect enough stable feature points. Use a textured surface and brighter light."
            )
        }

        let frames: [[String: Any]] = snapshot.frames.map { frame in
            [
                "file_path": frame.filePath,
                "w": frame.width,
                "h": frame.height,
                "fl_x": frame.fx,
                "fl_y": frame.fy,
                "cx": frame.cx,
                "cy": frame.cy,
                "camera_model": "OPENCV",
                "k1": 0.0,
                "k2": 0.0,
                "p1": 0.0,
                "p2": 0.0,
                "transform_matrix": frame.transformMatrix
            ]
        }

        let json: [String: Any] = [
            "camera_model": "OPENCV",
            "frames": frames,
            "ply_file_path": "points3D.ply"
        ]

        let jsonData = try JSONSerialization.data(
            withJSONObject: json,
            options: [.prettyPrinted, .sortedKeys]
        )
        try jsonData.write(
            to: root.appending(path: "transforms.json", directoryHint: .notDirectory),
            options: .atomic
        )

        try PointCloudFile.write(
            points: snapshot.featurePoints.map(\.position),
            colors: snapshot.featurePoints.map(\.color),
            to: root.appending(path: "points3D.ply", directoryHint: .notDirectory)
        )
    }
}

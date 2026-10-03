import CoreImage
import CoreImage.CIFilterBuiltins
import CoreVideo
import Foundation
import simd
import Vision

enum ObjectIsolationError: LocalizedError {
    case noForeground
    case renderFailed

    var errorDescription: String? {
        switch self {
        case .noForeground:
            "No clear foreground object was found in this frame."
        case .renderFailed:
            "The isolated object image could not be rendered."
        }
    }
}

/// Builds foreground-only training data for object/product scans.
///
/// Original camera photos remain untouched in \`images/\`. Vision produces a
/// second transparent image set for Gaussian training, and those same masks are
/// used to remove 3D seed points that only explain the table, wall or floor.
enum ObjectIsolationService {
    private static let maskLongEdge = 512

    private struct ForegroundMask: Sendable {
        let frame: CameraOnlyFrameMetadata
        let worldToCamera: simd_float4x4
        let width: Int
        let height: Int
        let alpha: [UInt8]

        func contains(_ point: SIMD3<Float>) -> Bool {
            let cameraPoint = worldToCamera * SIMD4<Float>(
                point.x,
                point.y,
                point.z,
                1
            )
            let depth = -cameraPoint.z
            guard depth > 0.02 else { return false }

            let u = Float(frame.fx) * cameraPoint.x / depth + Float(frame.cx)
            let v = Float(frame.cy) - Float(frame.fy) * cameraPoint.y / depth
            guard u.isFinite, v.isFinite,
                  u >= 0, u < Float(frame.width),
                  v >= 0, v < Float(frame.height)
            else {
                return false
            }

            let mx = min(
                width - 1,
                max(0, Int(u / Float(frame.width) * Float(width)))
            )
            let my = min(
                height - 1,
                max(0, Int(v / Float(frame.height) * Float(height)))
            )
            return alpha[my * width + mx] >= 32
        }
    }

    private struct IsolatedFrame: Sendable {
        let metadata: CameraOnlyFrameMetadata
        let mask: ForegroundMask
    }

    static func prepareTrainingSnapshot(
        snapshot: CameraOnlyCaptureSnapshot,
        root: URL,
        minimumFrames: Int
    ) async throws -> CameraOnlyCaptureSnapshot {
        guard !snapshot.frames.isEmpty else { return snapshot }

        let directory = root.appending(
            path: "isolated-images",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        var isolatedFrames: [IsolatedFrame] = []
        isolatedFrames.reserveCapacity(snapshot.frames.count)

        for (index, frame) in snapshot.frames.enumerated() {
            try Task.checkCancellation()

            let inputURL = root.appending(path: frame.filePath)
            let outputName = String(format: "foreground_%04d.png", index)
            let outputURL = directory.appending(
                path: outputName,
                directoryHint: .notDirectory
            )

            if let isolated = try? await isolateFrame(
                frame,
                inputURL: inputURL,
                outputURL: outputURL,
                relativeOutputPath: "isolated-images/\(outputName)"
            ) {
                isolatedFrames.append(isolated)
            }
        }

        // Difficult subjects still get a model. Only switch the whole dataset to
        // masked training when enough isolated views survived Vision.
        guard isolatedFrames.count >= max(1, minimumFrames) else {
            return snapshot
        }

        let filteredPoints = filterForegroundPoints(
            snapshot.featurePoints,
            masks: isolatedFrames.map(\.mask)
        )

        return CameraOnlyCaptureSnapshot(
            frames: isolatedFrames.map(\.metadata),
            featurePoints: filteredPoints.count >= 100
                ? filteredPoints
                : snapshot.featurePoints
        )
    }

    static func createTransparentPNG(
        imageAt inputURL: URL,
        outputURL: URL
    ) async throws {
        let data = try Data(contentsOf: inputURL)
        guard let source = CIImage(data: data) else {
            throw ObjectIsolationError.renderFailed
        }

        let context = CIContext(options: [.cacheIntermediates: false])
        guard let cgImage = context.createCGImage(source, from: source.extent) else {
            throw ObjectIsolationError.renderFailed
        }

        let handler = ImageRequestHandler(cgImage)
        let request = GenerateForegroundInstanceMaskRequest()
        guard let observation = try await handler.perform(request),
              !observation.allInstances.isEmpty
        else {
            throw ObjectIsolationError.noForeground
        }

        let maskedBuffer = try observation.generateMaskedImage(
            for: observation.allInstances,
            imageFrom: handler,
            croppedToInstancesExtent: false
        )
        let isolated = CIImage(cvPixelBuffer: maskedBuffer)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
            ?? CGColorSpaceCreateDeviceRGB()

        guard let png = context.pngRepresentation(
            of: isolated,
            format: .RGBA8,
            colorSpace: colorSpace,
            options: [:]
        ) else {
            throw ObjectIsolationError.renderFailed
        }

        try png.write(to: outputURL, options: .atomic)
    }

    private static func isolateFrame(
        _ frame: CameraOnlyFrameMetadata,
        inputURL: URL,
        outputURL: URL,
        relativeOutputPath: String
    ) async throws -> IsolatedFrame {
        let data = try Data(contentsOf: inputURL)
        guard let source = CIImage(data: data) else {
            throw ObjectIsolationError.renderFailed
        }

        let context = CIContext(options: [.cacheIntermediates: false])
        guard let cgImage = context.createCGImage(source, from: source.extent) else {
            throw ObjectIsolationError.renderFailed
        }

        let handler = ImageRequestHandler(cgImage)
        let request = GenerateForegroundInstanceMaskRequest()
        guard let observation = try await handler.perform(request),
              !observation.allInstances.isEmpty
        else {
            throw ObjectIsolationError.noForeground
        }

        let maskedBuffer = try observation.generateMaskedImage(
            for: observation.allInstances,
            imageFrom: handler,
            croppedToInstancesExtent: false
        )
        let isolated = CIImage(cvPixelBuffer: maskedBuffer)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
            ?? CGColorSpaceCreateDeviceRGB()

        guard let png = context.pngRepresentation(
            of: isolated,
            format: .RGBA8,
            colorSpace: colorSpace,
            options: [:]
        ) else {
            throw ObjectIsolationError.renderFailed
        }
        try png.write(to: outputURL, options: .atomic)

        guard let mask = makeMask(
            from: maskedBuffer,
            frame: frame,
            context: context
        ) else {
            throw ObjectIsolationError.renderFailed
        }

        return IsolatedFrame(
            metadata: CameraOnlyFrameMetadata(
                filePath: relativeOutputPath,
                width: frame.width,
                height: frame.height,
                fx: frame.fx,
                fy: frame.fy,
                cx: frame.cx,
                cy: frame.cy,
                transformMatrix: frame.transformMatrix
            ),
            mask: mask
        )
    }

    private static func makeMask(
        from sourceBuffer: CVPixelBuffer,
        frame: CameraOnlyFrameMetadata,
        context: CIContext
    ) -> ForegroundMask? {
        let source = CIImage(cvPixelBuffer: sourceBuffer)
        let sourceWidth = max(source.extent.width, 1)
        let sourceHeight = max(source.extent.height, 1)
        let longEdge = max(sourceWidth, sourceHeight)
        let scale = min(1, CGFloat(maskLongEdge) / longEdge)
        let width = max(1, Int((sourceWidth * scale).rounded()))
        let height = max(1, Int((sourceHeight * scale).rounded()))

        var output: CVPixelBuffer?
        let attributes: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true
        ]
        guard CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &output
        ) == kCVReturnSuccess,
        let output
        else {
            return nil
        }

        let normalized = source
            .transformed(
                by: CGAffineTransform(
                    translationX: -source.extent.minX,
                    y: -source.extent.minY
                )
            )
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        context.render(
            normalized,
            to: output,
            bounds: CGRect(x: 0, y: 0, width: width, height: height),
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)
        )

        CVPixelBufferLockBaseAddress(output, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(output, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(output) else { return nil }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(output)
        var alpha = [UInt8](repeating: 0, count: width * height)

        for y in 0..<height {
            let row = base
                .advanced(by: y * bytesPerRow)
                .assumingMemoryBound(to: UInt8.self)
            for x in 0..<width {
                alpha[y * width + x] = row[x * 4 + 3]
            }
        }

        return ForegroundMask(
            frame: frame,
            worldToCamera: matrix(fromRows: frame.transformMatrix).inverse,
            width: width,
            height: height,
            alpha: alpha
        )
    }

    private static func filterForegroundPoints(
        _ points: [CameraOnlyFeaturePoint],
        masks: [ForegroundMask]
    ) -> [CameraOnlyFeaturePoint] {
        guard !masks.isEmpty else { return points }

        let requiredVotes = masks.count >= 4 ? 2 : 1
        var result: [CameraOnlyFeaturePoint] = []
        result.reserveCapacity(points.count)

        for point in points {
            var votes = 0
            for mask in masks where mask.contains(point.position) {
                votes += 1
                if votes >= requiredVotes {
                    result.append(point)
                    break
                }
            }
        }

        return result
    }

    private static func matrix(
        fromRows rows: [[Double]]
    ) -> simd_float4x4 {
        guard rows.count == 4,
              rows.allSatisfy({ $0.count == 4 })
        else {
            return matrix_identity_float4x4
        }

        return simd_float4x4(columns: (
            SIMD4<Float>(
                Float(rows[0][0]), Float(rows[1][0]),
                Float(rows[2][0]), Float(rows[3][0])
            ),
            SIMD4<Float>(
                Float(rows[0][1]), Float(rows[1][1]),
                Float(rows[2][1]), Float(rows[3][1])
            ),
            SIMD4<Float>(
                Float(rows[0][2]), Float(rows[1][2]),
                Float(rows[2][2]), Float(rows[3][2])
            ),
            SIMD4<Float>(
                Float(rows[0][3]), Float(rows[1][3]),
                Float(rows[2][3]), Float(rows[3][3])
            )
        ))
    }
}

import CoreGraphics
import CoreImage
import CoreML
import CoreVideo
import Foundation
import simd

/// Adds a dense learned geometry prior before Gaussian optimization.
///
/// Depth Anything V2 predicts relative inverse depth. For each selected camera
/// view, this service projects ARKit's tracked metric feature points into the
/// depth map and robustly fits:
///
///     metricInverseDepth = scale * learnedDepth + offset
///
/// The calibrated map is then back-projected through the recorded camera
/// intrinsics/pose. ARKit remains the metric authority; the neural model only
/// fills spatial detail between sparse tracked features.
///
/// This is intentionally best-effort. If the bundled model is unavailable or a
/// frame cannot be calibrated, the original ARKit seed is preserved unchanged.
enum LearnedDepthSeedService {
    private static let modelName = "DepthAnythingV2SmallF16"

    static func enrich(
        snapshot: CameraOnlyCaptureSnapshot,
        root: URL,
        quality: CameraOnlyQualityProfile
    ) -> [CameraOnlyFeaturePoint] {
        guard quality.learnedDepthPriorEnabled,
              snapshot.frames.count >= quality.minimumFrameCount,
              !snapshot.featurePoints.isEmpty,
              let modelURL = Bundle.main.url(
                forResource: modelName,
                withExtension: "mlmodelc"
              )
        else {
            return snapshot.featurePoints
        }

        do {
            let configuration = MLModelConfiguration()
            configuration.computeUnits = .all
            let model = try MLModel(
                contentsOf: modelURL,
                configuration: configuration
            )

            guard let io = ModelIO(model: model) else {
                return snapshot.featurePoints
            }

            let context = CIContext(options: [.cacheIntermediates: false])
            guard let inputBuffer = makePixelBuffer(
                width: io.inputWidth,
                height: io.inputHeight,
                pixelFormat: io.inputPixelFormat
            ) else {
                return snapshot.featurePoints
            }

            var result = snapshot.featurePoints
            result.reserveCapacity(
                min(
                    snapshot.featurePoints.count + quality.depthPriorMaximumPoints,
                    snapshot.featurePoints.count + 160_000
                )
            )

            var voxels = Set<VoxelKey>()
            voxels.reserveCapacity(result.count + quality.depthPriorMaximumPoints)
            for point in result {
                voxels.insert(
                    VoxelKey(
                        point.position,
                        voxelSize: quality.depthPriorVoxelSize
                    )
                )
            }

            let keyframes = evenlySpacedIndices(
                count: snapshot.frames.count,
                desired: quality.depthPriorKeyframeCount
            )

            var generated = 0
            for index in keyframes {
                if generated >= quality.depthPriorMaximumPoints { break }

                let frame = snapshot.frames[index]
                let imageURL = root.appending(path: frame.filePath)
                guard let sourceImage = CIImage(contentsOf: imageURL) else {
                    continue
                }

                render(
                    sourceImage,
                    into: inputBuffer,
                    width: io.inputWidth,
                    height: io.inputHeight,
                    context: context
                )

                let input = try MLDictionaryFeatureProvider(dictionary: [
                    io.inputName: MLFeatureValue(pixelBuffer: inputBuffer)
                ])
                let prediction = try model.prediction(from: input)

                guard let depthBuffer = prediction
                    .featureValue(for: io.outputName)?
                    .imageBufferValue,
                      let depthMap = DepthMap(pixelBuffer: depthBuffer)
                else {
                    continue
                }

                let transform = simdMatrix(fromRows: frame.transformMatrix)
                guard let calibration = calibrate(
                    depthMap: depthMap,
                    frame: frame,
                    cameraTransform: transform,
                    anchors: snapshot.featurePoints,
                    minimumAnchors: quality.depthPriorMinimumAnchors
                ) else {
                    continue
                }

                let remaining = quality.depthPriorMaximumPoints - generated
                let newPoints = backProject(
                    depthMap: depthMap,
                    inputBuffer: inputBuffer,
                    frame: frame,
                    cameraTransform: transform,
                    calibration: calibration,
                    gridStride: quality.depthPriorGridStride,
                    limit: remaining,
                    voxelSize: quality.depthPriorVoxelSize,
                    occupiedVoxels: &voxels
                )
                generated += newPoints.count
                result.append(contentsOf: newPoints)
            }

            return result
        } catch {
            return snapshot.featurePoints
        }
    }

    private struct ModelIO {
        let inputName: String
        let outputName: String
        let inputWidth: Int
        let inputHeight: Int
        let inputPixelFormat: OSType

        init?(model: MLModel) {
            guard let input = model.modelDescription.inputDescriptionsByName
                .first(where: { $0.value.type == .image }),
                  let constraint = input.value.imageConstraint,
                  let output = model.modelDescription.outputDescriptionsByName
                .first(where: { $0.value.type == .image })
            else {
                return nil
            }

            inputName = input.key
            outputName = output.key
            inputWidth = constraint.pixelsWide
            inputHeight = constraint.pixelsHigh

            let requestedFormat = constraint.pixelFormatType
            switch requestedFormat {
            case kCVPixelFormatType_32ARGB,
                 kCVPixelFormatType_32BGRA:
                inputPixelFormat = requestedFormat
            default:
                // Apple's reference Depth Anything app uses a reusable 32ARGB
                // input buffer. Keep that as the compatibility fallback.
                inputPixelFormat = kCVPixelFormatType_32ARGB
            }
        }
    }

    private struct Calibration {
        let scale: Float
        let offset: Float
        let minimumMetricDepth: Float
        let maximumMetricDepth: Float

        func metricDepth(for learnedInverseDepth: Float) -> Float? {
            let inverseDepth = scale * learnedInverseDepth + offset
            guard inverseDepth.isFinite, inverseDepth > 0.0001 else {
                return nil
            }

            let depth = 1 / inverseDepth
            let lower = max(0.06, minimumMetricDepth * 0.65)
            let upper = min(10, maximumMetricDepth * 1.45)
            guard depth >= lower, depth <= upper else { return nil }
            return depth
        }
    }

    private struct VoxelKey: Hashable {
        let x: Int
        let y: Int
        let z: Int

        init(_ point: SIMD3<Float>, voxelSize: Float) {
            let size = max(voxelSize, 0.0005)
            x = Int(floor(point.x / size))
            y = Int(floor(point.y / size))
            z = Int(floor(point.z / size))
        }
    }

    private struct DepthMap {
        let width: Int
        let height: Int
        private let values: [Float]

        init?(pixelBuffer: CVPixelBuffer) {
            width = CVPixelBufferGetWidth(pixelBuffer)
            height = CVPixelBufferGetHeight(pixelBuffer)
            guard width > 0, height > 0 else { return nil }

            CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

            guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else {
                return nil
            }

            let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
            let format = CVPixelBufferGetPixelFormatType(pixelBuffer)
            var output = [Float](repeating: 0, count: width * height)

            if format == kCVPixelFormatType_OneComponent32Float ||
                format == kCVPixelFormatType_DepthFloat32 {
                for y in 0..<height {
                    let row = base.advanced(by: y * bytesPerRow)
                    for x in 0..<width {
                        let value = row.loadUnaligned(
                            fromByteOffset: x * MemoryLayout<Float>.size,
                            as: Float.self
                        )
                        output[y * width + x] = value
                    }
                }
            } else if format == kCVPixelFormatType_OneComponent16Half ||
                        format == kCVPixelFormatType_DepthFloat16 {
                for y in 0..<height {
                    let row = base.advanced(by: y * bytesPerRow)
                    for x in 0..<width {
                        let bits = row.loadUnaligned(
                            fromByteOffset: x * MemoryLayout<UInt16>.size,
                            as: UInt16.self
                        )
                        output[y * width + x] = Float(Float16(bitPattern: bits))
                    }
                }
            } else {
                return nil
            }

            values = output
        }

        func sample(x: Float, y: Float) -> Float? {
            guard x.isFinite, y.isFinite else { return nil }
            let ix = min(width - 1, max(0, Int(x.rounded())))
            let iy = min(height - 1, max(0, Int(y.rounded())))
            let value = values[iy * width + ix]
            return value.isFinite ? value : nil
        }
    }

    private static func calibrate(
        depthMap: DepthMap,
        frame: CameraOnlyFrameMetadata,
        cameraTransform: simd_float4x4,
        anchors: [CameraOnlyFeaturePoint],
        minimumAnchors: Int
    ) -> Calibration? {
        let worldToCamera = cameraTransform.inverse
        var pairs: [(learned: Float, metricInverse: Float, metricDepth: Float)] = []
        pairs.reserveCapacity(min(anchors.count, 4_096))

        let sourceWidth = Float(frame.width)
        let sourceHeight = Float(frame.height)

        for anchor in anchors {
            let cameraPoint = worldToCamera * SIMD4<Float>(
                anchor.position.x,
                anchor.position.y,
                anchor.position.z,
                1
            )
            let metricDepth = -cameraPoint.z
            guard metricDepth > 0.06, metricDepth < 10 else { continue }

            let u = Float(frame.fx) * cameraPoint.x / metricDepth + Float(frame.cx)
            let v = Float(frame.cy) - Float(frame.fy) * cameraPoint.y / metricDepth
            guard u >= 0, u < sourceWidth, v >= 0, v < sourceHeight else {
                continue
            }

            let dx = u / sourceWidth * Float(depthMap.width)
            let dy = v / sourceHeight * Float(depthMap.height)
            guard let learned = depthMap.sample(x: dx, y: dy),
                  learned > 0
            else {
                continue
            }

            pairs.append((learned, 1 / metricDepth, metricDepth))
            if pairs.count >= 4_096 { break }
        }

        guard pairs.count >= minimumAnchors,
              let firstFit = linearFit(pairs)
        else {
            return nil
        }

        let residuals = pairs.map {
            abs($0.metricInverse - (firstFit.scale * $0.learned + firstFit.offset))
        }
        let medianResidual = median(residuals)
        let threshold = max(0.02, medianResidual * 3.0)

        let inliers = pairs.filter {
            abs($0.metricInverse - (firstFit.scale * $0.learned + firstFit.offset)) <= threshold
        }

        guard inliers.count >= minimumAnchors,
              let fit = linearFit(inliers),
              fit.scale > 0
        else {
            return nil
        }

        let metricDepths = inliers.map(\.metricDepth).sorted()
        guard let minimumDepth = percentile(metricDepths, fraction: 0.05),
              let maximumDepth = percentile(metricDepths, fraction: 0.95),
              maximumDepth > minimumDepth
        else {
            return nil
        }

        return Calibration(
            scale: fit.scale,
            offset: fit.offset,
            minimumMetricDepth: minimumDepth,
            maximumMetricDepth: maximumDepth
        )
    }

    private static func linearFit(
        _ pairs: [(learned: Float, metricInverse: Float, metricDepth: Float)]
    ) -> (scale: Float, offset: Float)? {
        guard pairs.count >= 2 else { return nil }

        var sumX = 0.0
        var sumY = 0.0
        var sumXX = 0.0
        var sumXY = 0.0

        for pair in pairs {
            let x = Double(pair.learned)
            let y = Double(pair.metricInverse)
            sumX += x
            sumY += y
            sumXX += x * x
            sumXY += x * y
        }

        let n = Double(pairs.count)
        let denominator = n * sumXX - sumX * sumX
        guard abs(denominator) > 1e-12 else { return nil }

        let scale = (n * sumXY - sumX * sumY) / denominator
        let offset = (sumY - scale * sumX) / n
        guard scale.isFinite, offset.isFinite else { return nil }

        return (Float(scale), Float(offset))
    }

    private static func backProject(
        depthMap: DepthMap,
        inputBuffer: CVPixelBuffer,
        frame: CameraOnlyFrameMetadata,
        cameraTransform: simd_float4x4,
        calibration: Calibration,
        gridStride: Int,
        limit: Int,
        voxelSize: Float,
        occupiedVoxels: inout Set<VoxelKey>
    ) -> [CameraOnlyFeaturePoint] {
        guard limit > 0 else { return [] }

        let stride = max(4, gridStride)
        let borderX = max(stride, Int(Float(depthMap.width) * 0.04))
        let borderY = max(stride, Int(Float(depthMap.height) * 0.04))
        let sourceWidth = Float(frame.width)
        let sourceHeight = Float(frame.height)

        var output: [CameraOnlyFeaturePoint] = []
        output.reserveCapacity(min(limit, 4_096))

        CVPixelBufferLockBaseAddress(inputBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(inputBuffer, .readOnly) }

        for y in Swift.stride(
            from: borderY,
            to: depthMap.height - borderY,
            by: stride
        ) {
            for x in Swift.stride(
                from: borderX,
                to: depthMap.width - borderX,
                by: stride
            ) {
                if output.count >= limit { return output }

                guard let learned = depthMap.sample(
                    x: Float(x),
                    y: Float(y)
                ),
                learned > 0,
                let metricDepth = calibration.metricDepth(
                    for: learned
                ) else {
                    continue
                }

                let u = (Float(x) + 0.5) / Float(depthMap.width) * sourceWidth
                let v = (Float(y) + 0.5) / Float(depthMap.height) * sourceHeight

                let cameraX = (u - Float(frame.cx)) / Float(frame.fx) * metricDepth
                let cameraY = -(v - Float(frame.cy)) / Float(frame.fy) * metricDepth
                let cameraPoint = SIMD4<Float>(
                    cameraX,
                    cameraY,
                    -metricDepth,
                    1
                )
                let worldPoint4 = cameraTransform * cameraPoint
                let worldPoint = SIMD3<Float>(
                    worldPoint4.x,
                    worldPoint4.y,
                    worldPoint4.z
                )

                let voxel = VoxelKey(worldPoint, voxelSize: voxelSize)
                guard occupiedVoxels.insert(voxel).inserted else { continue }

                let color = sampleRGB(
                    inputBuffer,
                    x: min(
                        CVPixelBufferGetWidth(inputBuffer) - 1,
                        max(0, x)
                    ),
                    y: min(
                        CVPixelBufferGetHeight(inputBuffer) - 1,
                        max(0, y)
                    )
                ) ?? SIMD3<UInt8>(repeating: 128)

                output.append(
                    CameraOnlyFeaturePoint(
                        position: worldPoint,
                        color: color
                    )
                )
            }
        }

        return output
    }

    private static func makePixelBuffer(
        width: Int,
        height: Int,
        pixelFormat: OSType
    ) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        let attributes: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferMetalCompatibilityKey: true
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            pixelFormat,
            attributes as CFDictionary,
            &buffer
        )
        return status == kCVReturnSuccess ? buffer : nil
    }

    private static func render(
        _ source: CIImage,
        into buffer: CVPixelBuffer,
        width: Int,
        height: Int,
        context: CIContext
    ) {
        let sx = CGFloat(width) / max(source.extent.width, 1)
        let sy = CGFloat(height) / max(source.extent.height, 1)
        let image = source.transformed(
            by: CGAffineTransform(
                translationX: -source.extent.minX,
                y: -source.extent.minY
            )
        ).transformed(
            by: CGAffineTransform(scaleX: sx, y: sy)
        )
        context.render(
            image,
            to: buffer,
            bounds: CGRect(x: 0, y: 0, width: width, height: height),
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)
        )
    }

    private static func sampleRGB(
        _ buffer: CVPixelBuffer,
        x: Int,
        y: Int
    ) -> SIMD3<UInt8>? {
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let row = base
            .advanced(by: y * CVPixelBufferGetBytesPerRow(buffer))
            .assumingMemoryBound(to: UInt8.self)
        let offset = x * 4

        switch CVPixelBufferGetPixelFormatType(buffer) {
        case kCVPixelFormatType_32ARGB:
            return SIMD3(row[offset + 1], row[offset + 2], row[offset + 3])
        case kCVPixelFormatType_32BGRA:
            return SIMD3(row[offset + 2], row[offset + 1], row[offset])
        default:
            return nil
        }
    }

    private static func simdMatrix(
        fromRows rows: [[Double]]
    ) -> simd_float4x4 {
        guard rows.count == 4,
              rows.allSatisfy({ $0.count == 4 })
        else {
            return matrix_identity_float4x4
        }

        return simd_float4x4(columns: (
            SIMD4<Float>(
                Float(rows[0][0]),
                Float(rows[1][0]),
                Float(rows[2][0]),
                Float(rows[3][0])
            ),
            SIMD4<Float>(
                Float(rows[0][1]),
                Float(rows[1][1]),
                Float(rows[2][1]),
                Float(rows[3][1])
            ),
            SIMD4<Float>(
                Float(rows[0][2]),
                Float(rows[1][2]),
                Float(rows[2][2]),
                Float(rows[3][2])
            ),
            SIMD4<Float>(
                Float(rows[0][3]),
                Float(rows[1][3]),
                Float(rows[2][3]),
                Float(rows[3][3])
            )
        ))
    }

    private static func evenlySpacedIndices(
        count: Int,
        desired: Int
    ) -> [Int] {
        guard count > 0 else { return [] }
        let sampleCount = min(count, max(1, desired))
        guard sampleCount > 1 else { return [count / 2] }

        let denominator = Double(sampleCount - 1)
        return (0..<sampleCount).map { index in
            Int(
                (
                    Double(index) *
                    Double(count - 1) /
                    denominator
                ).rounded()
            )
        }
    }

    private static func median(_ values: [Float]) -> Float {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) * 0.5
        }
        return sorted[middle]
    }

    private static func percentile(
        _ sortedValues: [Float],
        fraction: Double
    ) -> Float? {
        guard !sortedValues.isEmpty else { return nil }
        let clamped = min(max(fraction, 0), 1)
        let index = Int(
            (
                clamped *
                Double(sortedValues.count - 1)
            ).rounded()
        )
        return sortedValues[index]
    }
}

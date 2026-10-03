import CoreVideo

/// Relative sharpness of a preview buffer.
///
/// Motion blur is the single most destructive input error in photogrammetry: a
/// soft frame does not merely contribute less, it contributes *wrong* feature
/// matches and can pull the whole alignment off. One bad frame is worse than a
/// missing angle, which is why blurred shots are dropped rather than kept.
///
/// The metric is gradient energy — mean squared difference between horizontally
/// adjacent pixels. It has no absolute meaning, only relative: the same scene shot
/// sharp scores several times higher than the same scene shot soft. That is enough
/// to compare frames within one session.
enum SharpnessMeter {

    static func score(_ buffer: CVPixelBuffer) -> Float? {
        score(buffer, rowStride: 2, columnStride: 1)
    }

    /// Lower-cost sampling for multi-megapixel live AR frames.
    ///
    /// It measures the same adjacent-pixel gradient energy but samples fewer
    /// positions, preserving the relative blur signal without scanning every
    /// 4K pixel on the ARSession delegate queue.
    static func scoreFast(_ buffer: CVPixelBuffer) -> Float? {
        score(buffer, rowStride: 4, columnStride: 4)
    }

    private static func score(
        _ buffer: CVPixelBuffer,
        rowStride: Int,
        columnStride: Int
    ) -> Float? {
        let format = CVPixelBufferGetPixelFormatType(buffer)

        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        guard width > 8, height > 8 else { return nil }

        switch format {
        case kCVPixelFormatType_32BGRA:
            guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
            return gradientEnergy(
                base: base,
                bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                width: width,
                height: height,
                bytesPerPixel: 4,
                channelOffset: 1,
                rowStride: rowStride,
                columnStride: columnStride
            )

        case kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
             kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange:
            guard let base = CVPixelBufferGetBaseAddressOfPlane(buffer, 0) else { return nil }
            return gradientEnergy(
                base: base,
                bytesPerRow: CVPixelBufferGetBytesPerRowOfPlane(buffer, 0),
                width: CVPixelBufferGetWidthOfPlane(buffer, 0),
                height: CVPixelBufferGetHeightOfPlane(buffer, 0),
                bytesPerPixel: 1,
                channelOffset: 0,
                rowStride: rowStride,
                columnStride: columnStride
            )

        default:
            return nil
        }
    }

    private static func gradientEnergy(
        base: UnsafeMutableRawPointer,
        bytesPerRow: Int,
        width: Int,
        height: Int,
        bytesPerPixel: Int,
        channelOffset: Int,
        rowStride: Int,
        columnStride: Int
    ) -> Float {
        var total: Double = 0
        var samples = 0

        let safeRowStride = max(1, rowStride)
        let safeColumnStride = max(1, columnStride)

        for row in stride(from: 0, to: height, by: safeRowStride) {
            let rowBase = base
                .advanced(by: row * bytesPerRow)
                .assumingMemoryBound(to: UInt8.self)

            for column in stride(
                from: 0,
                to: width - 1,
                by: safeColumnStride
            ) {
                let left = Int(rowBase[column * bytesPerPixel + channelOffset])
                let right = Int(
                    rowBase[(column + 1) * bytesPerPixel + channelOffset]
                )
                let difference = Double(right - left)
                total += difference * difference
                samples += 1
            }
        }

        return samples > 0 ? Float(total / Double(samples)) : 0
    }
}

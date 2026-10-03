import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
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

enum ObjectIsolationService {
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
}

import Foundation
import SplatIO

enum GaussianExportService {
    static func exportPLY(
        from sourceURL: URL,
        to destinationURL: URL
    ) async throws -> URL {
        try Task.checkCancellation()

        var pointCount = 0
        let countingReader = try AutodetectSceneReader(sourceURL)
        for try await batch in try await countingReader.read() {
            try Task.checkCancellation()
            pointCount += batch.count
        }

        guard pointCount > 0 else {
            throw ExportError.emptyModel
        }

        try? FileManager.default.removeItem(at: destinationURL)

        let writer = try SplatPLYSceneWriter(
            toFileAtPath: destinationURL.path(percentEncoded: false)
        )
        try await writer.start(pointCount: pointCount)

        do {
            let writingReader = try AutodetectSceneReader(sourceURL)
            for try await batch in try await writingReader.read() {
                try Task.checkCancellation()
                try await writer.write(batch)
            }
            try await writer.close()
            return destinationURL
        } catch {
            try? await writer.close()
            try? FileManager.default.removeItem(at: destinationURL)
            throw error
        }
    }

    enum ExportError: LocalizedError {
        case emptyModel

        var errorDescription: String? {
            switch self {
            case .emptyModel:
                "The Gaussian model contains no points to export."
            }
        }
    }
}

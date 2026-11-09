import Foundation

enum GoIPAValidator {
    private struct Verdict: Decodable {
        let ok: Bool
        let scanned: Int?
        let compared: Int?
        let error: String?
        let still_encrypted: [String]?
        let all_zero: [String]?
        let skipped: [String]?
        let missing: [String]?
    }

    // Invokes the REAL pinned londek/ipadecrypt Go verification pipeline,
    // built as an iOS arm64 c-archive and linked into this process.
    static func verify(output:URL, original:URL) throws {
        let raw = output.path.withCString { outputPath in
            original.path.withCString { sourcePath in
                IPADecryptVerify(UnsafeMutablePointer(mutating:outputPath),
                                 UnsafeMutablePointer(mutating:sourcePath))
            }
        }
        guard let raw else {throw DecryptionFailure.invalid("Upstream Go verifier returned no result")}
        defer {IPADecryptFreeString(raw)}
        let message=String(cString:raw)
        guard let resultData=message.data(using:.utf8),
              let verdict=try? JSONDecoder().decode(Verdict.self,from:resultData) else {
            throw DecryptionFailure.invalid("Invalid upstream Go verification result: \(message.prefix(600))")
        }
        guard verdict.ok else {
            let details=[verdict.error,
                         verdict.still_encrypted?.joined(separator:", "),
                         verdict.all_zero?.joined(separator:", "),
                         verdict.skipped?.joined(separator:", "),
                         verdict.missing?.joined(separator:", ")]
                .compactMap{$0}.filter{!$0.isEmpty}.joined(separator:"; ")
            throw DecryptionFailure.invalid("ipadecrypt verification failed: \(details.isEmpty ? "encrypted/unchanged Mach-O bytes or other mismatches" : details)")
        }
        try FairPlayCore.require((verdict.compared ?? 0) > 0 &&
                                 (verdict.scanned ?? 0) > 0,
                                 "ipadecrypt did not compare any Mach-O executable")
    }
}

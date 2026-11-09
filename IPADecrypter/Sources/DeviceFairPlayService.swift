import Foundation
import ZIPFoundation

// FairPlayed-style licensed device VM backend.
// No credentials are requested, retrieved, copied or exported.
enum DeviceFairPlayService {
    private static let fm = FileManager.default
    static func embeddedFolders() -> [URL] {
        let root = Bundle.main.bundleURL.appendingPathComponent("EmbeddedPayload", isDirectory: true)
        return (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys:[.isDirectoryKey]))?
            .filter { (try? $0.resourceValues(forKeys:[.isDirectoryKey]).isDirectory) == true } ?? []
    }

    private static func entropy(_ bytes:Data) -> Double {
        guard !bytes.isEmpty else { return 0 }
        var counts=[Int](repeating:0,count:256)
        for value in bytes {counts[Int(value)] += 1}
        return counts.reduce(0.0) { sum, n in
            if n == 0 {return sum}
            let fraction=Double(n)/Double(bytes.count)
            return sum-fraction*log2(fraction)
        }
    }
    private static func opcodeWords(_ bytes:Data) -> Int {
        guard bytes.count>=4 else {return 0}
        var count=0
        var i=0
        while i+4<=bytes.count {
            let word=UInt32(bytes[i]) | UInt32(bytes[i+1]) << 8 |
                     UInt32(bytes[i+2]) << 16 | UInt32(bytes[i+3]) << 24
            if word==0xd65f03c0 || word==0xd503237f || word==0xd65f0fff {count+=1}
            i+=4
        }
        return count
    }

    static func decryptEmbedded(folder source:URL) throws -> DecryptionOutput {
        let installed=Bundle.main.bundleURL.appendingPathComponent("EmbeddedPayload",isDirectory:true)
        try FairPlayCore.require(source.deletingLastPathComponent().standardizedFileURL==installed.standardizedFileURL,
                                 "Select a bundled, preinstalled payload, not a Files import.")
        let task=fm.temporaryDirectory.appendingPathComponent("device-decrypt-"+UUID().uuidString,isDirectory:true)
        defer {try? fm.removeItem(at:task)}
        let payload=task.appendingPathComponent("Payload",isDirectory:true)
        try fm.createDirectory(at:payload,withIntermediateDirectories:true)
        let target=payload.appendingPathComponent(source.lastPathComponent+".app",isDirectory:true)
        try fm.copyItem(at:source,to:target)
        guard let iter=fm.enumerator(at:source,includingPropertiesForKeys:[.isRegularFileKey,.isSymbolicLinkKey]) else {
            throw DecryptionFailure.invalid("Cannot enumerate embedded app bundle")
        }
        var binaries=0
        var pages=0
        for case let file as URL in iter {
            let flags=try file.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey])
            guard flags.isRegularFile == true && flags.isSymbolicLink != true else {continue}
            let attrs=try fm.attributesOfItem(atPath:file.path)
            guard (attrs[.size] as? NSNumber)?.intValue ?? 0 >= 4096 else {continue}
            guard let handle=try? FileHandle(forReadingFrom:file) else {continue}
            let magic=handle.readData(ofLength:4)
            try? handle.close()
            if magic != Data([0xcf,0xfa,0xed,0xfe]) &&
               magic != Data([0xca,0xfe,0xba,0xbe]) &&
               magic != Data([0xca,0xfe,0xba,0xbf]) {continue}
            let original=try Data(contentsOf:file)
            let infos=try FairPlayCore.encryptionSlices(in:original)
            if infos.isEmpty {continue}
            var output=original
            for info in infos {
                var clear=[UInt8](repeating:0,count:info.cryptsize)
                var osError:Int32=0
                var readPages:UInt32=0
                let ret = clear.withUnsafeMutableBufferPointer { memory -> Int32 in
                    file.path.withCString { path in
                        fp_device_decrypt_pages(path,
                            UInt64(info.base),UInt32(info.cryptoff),UInt32(info.cryptsize),
                            0x0100000c,info.subtype,
                            memory.baseAddress,UInt32(memory.count),
                            &osError,&readPages)
                    }
                }
                try FairPlayCore.require(ret==0, "Device FairPlay mapping failed (stage \(ret), OS \(osError), pages \(readPages)). This IPA may need a valid license or this mapping is unsupported.")
                let start=info.base+info.cryptoff
                let ciphertext=original.subdata(in:start..<(start+info.cryptsize))
                let plaintext=Data(clear)
                try FairPlayCore.require(ciphertext != plaintext,"Device returned unchanged ciphertext")
                // Check changed bytes look like instructions, rather than random ciphertext.
                try FairPlayCore.require(entropy(ciphertext)>7.5 &&
                                         entropy(plaintext)<entropy(ciphertext) &&
                                         opcodeWords(plaintext)>opcodeWords(ciphertext),
                                         "VM mapping returned bytes that do not look like decrypted ARM64 code")
                output.replaceSubrange(start..<(start+info.cryptsize),with:plaintext)
                for i in 0..<4 {output[info.cryptidOffset+i]=0}
                pages+=Int(readPages)
            }
            let rel=String(file.path.dropFirst(source.path.count+1))
            let destination=target.appendingPathComponent(rel)
            try output.write(to:destination,options:.atomic)
            binaries+=1
        }
        try FairPlayCore.require(binaries>0 && pages>0,"No embedded Mach-O pages were decrypted")
        // Never export private account-bound licence records or stale code signature bundles.
        guard let cleanup=fm.enumerator(at:target,includingPropertiesForKeys:nil) else {
            throw DecryptionFailure.invalid("Unable to enumerate output for cleanup")
        }
        var removed:[URL]=[]
        while let p=cleanup.nextObject() as? URL {
            if p.lastPathComponent=="SC_Info" || p.lastPathComponent=="_CodeSignature" {
                removed.append(p)
                cleanup.skipDescendants()
            }
        }
        for url in removed.sorted(by:{$0.path.count>$1.path.count}) {
            if fm.fileExists(atPath:url.path) {try fm.removeItem(at:url)}
        }
        // Keep result in app Documents. No network transfer occurs.
        let documents=fm.urls(for:.documentDirectory,in:.userDomainMask)[0]
        let folder=documents.appendingPathComponent("Decrypted",isDirectory:true)
        try fm.createDirectory(at:folder,withIntermediateDirectories:true)
        let url=folder.appendingPathComponent(source.lastPathComponent+"-device-\(UUID().uuidString.prefix(8))-decrypted.ipa")
        do {
            try fm.zipItem(at:task,to:url,shouldKeepParent:false,compressionMethod:.deflate)
            let inspected=try IPAService.inspect(ipa:url)
            try FairPlayCore.require(inspected.encryptedPages==0,"Exported IPA still has encrypted main executable")
        } catch {
            try? fm.removeItem(at:url)
            throw error
        }
        return .init(url:url,binaries:binaries,pages:pages)
    }
}

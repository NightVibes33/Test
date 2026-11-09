// IPAService.swift - real on-device ZIP extraction, FairPlay decrypt and repackaging.
import Foundation
import ZIPFoundation

struct IPAInspection {
    let title: String
    let identifier: String
    let version: String
    let encryptedPages: Int
    let hasLicenseRecords: Bool
    let mainExecutable: String
}

struct DecryptionOutput {
    let url: URL
    let binaries: Int
    let pages: Int
}

enum IPAService {
    static let fm = FileManager.default

    private static func unpack(at ipa: URL, into target: URL) throws {
        let archive = try Archive(url: ipa, accessMode: .read)
        let entries = Array(archive)
        let names = entries.map(\.path)
        try FairPlayCore.require(Set(names).count == names.count, "IPA contains duplicate ZIP entries")
        try FairPlayCore.require(names.contains(where:{$0.hasPrefix("Payload/") && $0.contains(".app/")}), "Not an iOS IPA (missing Payload/*.app)")
        try fm.createDirectory(at:target,withIntermediateDirectories:true)
        try fm.unzipItem(at:ipa,to:target)
    }

    private static func bundleRoot(in directory: URL) throws -> URL {
        let payload = directory.appendingPathComponent("Payload",isDirectory:true)
        let bundles = try fm.contentsOfDirectory(at:payload,includingPropertiesForKeys:nil)
            .filter{$0.pathExtension=="app"}
        try FairPlayCore.require(bundles.count==1,"Expected exactly one Payload/*.app")
        return bundles[0]
    }

    private static func metadata(_ bundle:URL) throws -> (String,String,String,String) {
        let info=bundle.appendingPathComponent("Info.plist")
        let plist=try PropertyListSerialization.propertyList(from:Data(contentsOf:info),format:nil)
        guard let dict=plist as? [String:Any], let exec=dict["CFBundleExecutable"] as? String else {
            throw DecryptionFailure.invalid("App Info.plist missing CFBundleExecutable")
        }
        return (
          dict["CFBundleDisplayName"] as? String ?? dict["CFBundleName"] as? String ?? bundle.deletingPathExtension().lastPathComponent,
          dict["CFBundleIdentifier"] as? String ?? "unknown",
          dict["CFBundleShortVersionString"] as? String ?? "?",
          exec
        )
    }

    static func inspect(ipa:URL) throws -> IPAInspection {
        let scratch=fm.temporaryDirectory.appendingPathComponent("ipa-inspect-"+UUID().uuidString,isDirectory:true)
        defer {try? fm.removeItem(at:scratch)}
        try unpack(at:ipa,into:scratch)
        let bundle=try bundleRoot(in:scratch)
        let (title,id,version,executable)=try metadata(bundle)
        let binary=try Data(contentsOf:bundle.appendingPathComponent(executable))
        let infos=try FairPlayCore.encryptionSlices(in:binary)
        let pages=infos.reduce(0){$0+$1.cryptsize/FairPlayCore.pageSize}
        let sc=bundle.appendingPathComponent("SC_Info",isDirectory:true)
        let sinfs=(try? fm.contentsOfDirectory(atPath:sc.path)) ?? []
        let hasLicense=sinfs.contains(where:{$0.hasSuffix(".sinf")}) && sinfs.contains(where:{$0.hasSuffix(".supf")})
        return IPAInspection(title:title,identifier:id,version:version,encryptedPages:pages,hasLicenseRecords:hasLicense,mainExecutable:executable)
    }

    private static func matchingSinf(for supf:URL, binaryStem:String, root:URL) throws -> URL {
        let sc=supf.deletingLastPathComponent()
        let preferred=sc.appendingPathComponent(binaryStem + (supf.lastPathComponent.hasSuffix(".v5.supf") ? ".v4.sinf":".sinf"))
        if fm.fileExists(atPath:preferred.path) {return preferred}
        let standard=sc.appendingPathComponent(binaryStem+".sinf")
        if fm.fileExists(atPath:standard.path) {return standard}
        var bundle=sc.deletingLastPathComponent()
        while bundle.path.hasPrefix(root.path+"/") {
            if bundle.pathExtension=="app" {
                let others=bundle.appendingPathComponent("SC_Info",isDirectory:true)
                if let files=try? fm.contentsOfDirectory(at:others,includingPropertiesForKeys:nil) {
                    if let file=files.first(where:{$0.lastPathComponent==bundle.deletingPathExtension().lastPathComponent+".sinf"}) {return file}
                    if let file=files.first(where:{$0.pathExtension=="sinf"}) {return file}
                }
            }
            if bundle == root {break}
            bundle=bundle.deletingLastPathComponent()
        }
        throw DecryptionFailure.invalid("Matching SINF not found for \(binaryStem)")
    }

    static func decrypt(ipa:URL, credential:Data) throws -> DecryptionOutput {
        try FairPlayCore.require(credential.count==16,"The account credential file must be exactly 16 bytes")
        let work=fm.temporaryDirectory.appendingPathComponent("ipa-decrypt-"+UUID().uuidString,isDirectory:true)
        defer {try? fm.removeItem(at:work)}
        try unpack(at:ipa,into:work)
        let bundle=try bundleRoot(in:work)
        let (title,id,_,_)=try metadata(bundle)
        let enumerator=fm.enumerator(at:work,includingPropertiesForKeys:[.isDirectoryKey],options:[])
        var supfs:[URL]=[]
        var scInfos:[URL]=[]
        var signatureDirs:[URL]=[]
        while let entry=enumerator?.nextObject() as? URL {
            if entry.lastPathComponent=="SC_Info" {
                scInfos.append(entry)
            } else if entry.lastPathComponent=="_CodeSignature" {
                signatureDirs.append(entry)
            } else if entry.lastPathComponent.hasSuffix(".supf") && entry.deletingLastPathComponent().lastPathComponent=="SC_Info" {
                supfs.append(entry)
            }
        }
        try FairPlayCore.require(!supfs.isEmpty,"No supported SINF/SUPF FairPlay records present")
        // Prefer version-5 page records over version-3 for each binary.
        supfs.sort{
            let a=$0.path.replacingOccurrences(of:".v5.supf",with:".supf")
            let b=$1.path.replacingOccurrences(of:".v5.supf",with:".supf")
            if a==b {return $0.lastPathComponent.hasSuffix(".v5.supf")}
            return a<b
        }
        var processed=Set<String>()
        var binaries=0
        var pages=0
        for supf in supfs {
            let stem=supf.lastPathComponent.hasSuffix(".v5.supf")
                ? String(supf.lastPathComponent.dropLast(".v5.supf".count))
                : String(supf.lastPathComponent.dropLast(".supf".count))
            let candidate=supf.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(stem)
            let resolved=candidate.resolvingSymlinksInPath()
            try FairPlayCore.require(resolved.path.hasPrefix(work.path+"/"),"Unsafe symlink outside working directory")
            if processed.contains(resolved.path) {continue}
            guard fm.fileExists(atPath:resolved.path) else { continue }
            let input=try Data(contentsOf:resolved)
            let slices=try FairPlayCore.encryptionSlices(in:input)
            if slices.isEmpty {continue}
            let sinf=try matchingSinf(for:supf,binaryStem:stem,root:work)
            let (plain,decryptedPages)=try FairPlayCore.decrypt(
                binary:input,
                sinf:Data(contentsOf:sinf),
                supf:Data(contentsOf:supf),
                credential:credential
            )
            try plain.write(to:resolved,options:.atomic)
            processed.insert(resolved.path)
            binaries+=1
            pages+=decryptedPages
        }
        try FairPlayCore.require(binaries>0 && pages>0,"No encrypted binaries could be decrypted")
        // Remove owner/account FairPlay records. Discard invalid old signature
        // envelopes; the exported IPA must be re-signed for normal installation.
        for dir in (scInfos+signatureDirs).sorted(by:{$0.path.count>$1.path.count}) {
            if fm.fileExists(atPath:dir.path) {try fm.removeItem(at:dir)}
        }
        let destination=fm.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("Decrypted",isDirectory:true)
        try fm.createDirectory(at:destination,withIntermediateDirectories:true)
        let safeName=title.replacingOccurrences(of:"[^A-Za-z0-9_-]",with:"-",options:.regularExpression)
        let name="\(safeName)-\(id.replacingOccurrences(of:".",with:"-"))-\(UUID().uuidString.prefix(8))-decrypted.ipa"
        let output=destination.appendingPathComponent(name)
        do {
            try fm.zipItem(at:work,to:output,shouldKeepParent:false,compressionMethod:.deflate)
            let verify=try Archive(url:output,accessMode:.read)
            let names=Array(verify).map(\.path)
            try FairPlayCore.require(names.contains(where:{$0.hasPrefix("Payload/") && $0.contains(".app/Info.plist")}),"Repacked output lacks app bundle")
            try FairPlayCore.require(!names.contains(where:{$0.contains("/SC_Info/")}),"Output still contains private FairPlay account records")
            // Ensure output Mach-O is no longer flagged encrypted.
            let after=try inspect(ipa:output)
            try FairPlayCore.require(after.encryptedPages==0,"Output executable is still marked encrypted")
        } catch {
            try? fm.removeItem(at:output)
            throw error
        }
        return DecryptionOutput(url:output,binaries:binaries,pages:pages)
    }
}

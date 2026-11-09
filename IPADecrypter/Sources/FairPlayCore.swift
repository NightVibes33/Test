// IPADecrypter FairPlayCore.swift
// GPL-3.0-or-later. Port of independently derived FairPlay page-key algorithm
// described by EthanArbuckle/fairplay-decrypt. Requires account-owned credential.
import Foundation
import CryptoKit
import CommonCrypto

enum DecryptionFailure: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case .invalid(let s) = self { return s } else { return "Unknown decryption error" } }
}

struct EncryptionSlice {
    let base: Int
    let cryptoff: Int
    let cryptsize: Int
    let cryptidOffset: Int
    let subtype: UInt32
}

enum FairPlayCore {
    static let pageSize = 4096
    private static let arm64: UInt32 = 0x0100000c
    private static let roundSelectors = [
        [(0,1),(2,3),(4,5),(6,7)],
        [(2,1),(0,3),(4,7),(6,5)],
        [(2,0),(4,1),(6,3),(7,5)],
        [(1,2),(4,0),(7,3),(5,6)]
    ]
    private static let roundConstants: [UInt64] = [0x68547c2e, 0x7e05e1de, 0xd495038b, 0x0ab24add]
    private static let finalSelectors = [(0,1,2,3), (0,2,4,6), (0,3,5,7), (4,5,6,7)]
    private static let finalConstants: [UInt64] = [0x5b7198c7, 0xeb5de22c, 0x0f8aa8fa, 0xf6e1bb3f]
    static func require(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        if try !condition() { throw DecryptionFailure.invalid(message) }
    }
    static func u32(_ d: Data, _ pos: Int, big: Bool = false) throws -> UInt32 {
        try require(pos >= 0 && pos <= d.count - 4, "Truncated 32-bit field")
        let a = (0..<4).map { UInt32(d[pos + $0]) }
        return big ? (a[0] << 24 | a[1] << 16 | a[2] << 8 | a[3])
                   : (a[0] | a[1] << 8 | a[2] << 16 | a[3] << 24)
    }
    private static func u64(_ d: Data, _ pos: Int) throws -> UInt64 {
        (UInt64(try u32(d,pos,big:true)) << 32) | UInt64(try u32(d,pos+4,big:true))
    }
    private static func bytes(_ d: Data, _ start: Int, _ count: Int) throws -> Data {
        try require(start >= 0 && count >= 0 && start <= d.count && count <= d.count-start, "Truncated FairPlay record")
        return d.subdata(in: start..<(start + count))
    }
    private static func replaceU32LE(_ d: inout Data, _ offset: Int, _ value: UInt32) {
        for i in 0..<4 { d[offset + i] = UInt8(truncatingIfNeeded: value >> (i*8)) }
    }

    static func encryptionSlices(in data: Data) throws -> [EncryptionSlice] {
        try require(data.count >= 32, "Executable is too small")
        let magic = Array(data.prefix(4))
        var slices: [(Int,Int,UInt32)] = []
        if magic == [0xca,0xfe,0xba,0xbe] || magic == [0xca,0xfe,0xba,0xbf] {
            let fat64 = magic[3] == 0xbf
            let n = Int(try u32(data,4,big:true))
            try require(n > 0 && n <= 16, "Invalid FAT Mach-O table")
            let stride = fat64 ? 32 : 20
            try require(8+n*stride <= data.count, "Truncated FAT table")
            for i in 0..<n {
                let pos = 8+i*stride
                if try u32(data,pos,big:true) == arm64 {
                    let subtype = try u32(data,pos+4,big:true)
                    let off = try fat64 ? u64(data,pos+8) : UInt64(u32(data,pos+8,big:true))
                    let len = try fat64 ? u64(data,pos+16) : UInt64(u32(data,pos+12,big:true))
                    try require(off <= UInt64(Int.max) && len <= UInt64(Int.max), "FAT slice too large")
                    slices.append((Int(off),Int(len),subtype))
                }
            }
            try require(!slices.isEmpty, "No arm64 slice in FAT executable")
        } else if magic == [0xcf,0xfa,0xed,0xfe] {
            slices = [(0,data.count,try u32(data,8))]
        } else {
            throw DecryptionFailure.invalid("Unsupported Mach-O architecture; arm64 required")
        }
        var results:[EncryptionSlice] = []
        for (base,length,subtype) in slices {
            try require(base >= 0 && length >= 32 && base <= data.count && length <= data.count-base, "Mach-O slice outside executable")
            try require(try u32(data,base) == 0xfeedfacf && u32(data,base+4) == arm64, "Invalid arm64 Mach-O")
            let ncmds = Int(try u32(data,base+16))
            let sizeofcmds = Int(try u32(data,base+20))
            try require(ncmds <= 1000 && sizeofcmds >= 0 && sizeofcmds <= length-32, "Invalid Mach-O commands")
            var pos=base+32
            let end=pos+sizeofcmds
            var found=0
            for _ in 0..<ncmds {
                try require(pos+8 <= end, "Truncated load command")
                let cmd=try u32(data,pos)
                let size=Int(try u32(data,pos+4))
                try require(size >= 8 && size <= end-pos, "Invalid load command size")
                if cmd == 0x2c {
                    found += 1
                    try require(size >= 24, "Short LC_ENCRYPTION_INFO_64")
                    let off=Int(try u32(data,pos+8))
                    let len=Int(try u32(data,pos+12))
                    let cryptid=try u32(data,pos+16)
                    if cryptid != 0 {
                        try require(cryptid == 1 && len > 0 && len % pageSize == 0, "Unsupported FairPlay cryptid/size")
                        try require(off >= 0 && off <= length && len <= length-off && pos+16 < base+off, "Invalid encrypted page range")
                        results.append(.init(base:base,cryptoff:off,cryptsize:len,cryptidOffset:pos+16,subtype:subtype))
                    }
                }
                pos += size
            }
            try require(pos == end && found <= 1, "Invalid Mach-O encryption commands")
        }
        return results
    }

    private struct Atom { let tag: String; let start: Int; let end: Int }
    private static func atoms(_ d:Data, from:Int, to:Int) throws -> [Atom] {
        var result:[Atom]=[]
        var cursor=from
        while cursor < to {
            try require(cursor+8 <= to, "Truncated SINF atom")
            let size=Int(try u32(d,cursor,big:true))
            try require(size >= 8 && size <= to-cursor, "Invalid SINF atom size")
            let tag=String(data:try bytes(d,cursor+4,4),encoding:.ascii) ?? ""
            result.append(.init(tag:tag,start:cursor+8,end:cursor+size))
            cursor += size
        }
        return result
    }
    private static func sinfField(_ sinf:Data, _ name:String) throws -> Data {
        let roots=try atoms(sinf,from:0,to:sinf.count)
        try require(roots.count == 1 && roots[0].tag == "sinf", "Missing outer sinf record")
        let children=try atoms(sinf,from:roots[0].start,to:roots[0].end).filter{$0.tag=="schi"}
        try require(children.count == 1, "Missing schi FairPlay container")
        let fields=try atoms(sinf,from:children[0].start,to:children[0].end).filter{$0.tag==name}
        try require(fields.count == 1, "Missing FairPlay \(name) field")
        return try bytes(sinf,fields[0].start,fields[0].end-fields[0].start)
    }

    private static func aes(_ source:Data, key:Data, iv:Data? = nil, decrypt:Bool) throws -> Data {
        try require(key.count==16 && source.count%16==0 && (iv==nil || iv!.count==16), "Bad AES-128 input length")
        var out=Data(count:source.count+16)
        let capacity=out.count
        var written=0
        let zeroIV=iv ?? Data(repeating:0,count:16)
        let opts=CCOptions(iv == nil ? kCCOptionECBMode : 0)
        let status:CCCryptorStatus=out.withUnsafeMutableBytes { dest in
            source.withUnsafeBytes { src in
                key.withUnsafeBytes { k in
                    zeroIV.withUnsafeBytes { v in
                        CCCrypt(CCOperation(decrypt ? kCCDecrypt:kCCEncrypt),CCAlgorithm(kCCAlgorithmAES),opts,
                                k.baseAddress,16,iv == nil ? nil:v.baseAddress,
                                src.baseAddress,source.count,dest.baseAddress,capacity,&written)
                    }
                }
            }
        }
        try require(status==kCCSuccess && written==source.count, "AES processing failed")
        return Data(out.prefix(written))
    }
    private static func deriveWork(_ credential:Data, _ sinf:Data) throws -> Data {
        try require(credential.count == 16, "Credential must be precisely 16 bytes")
        let name=try sinfField(sinf,"name")
        let nameValue=Data(name.prefix(while:{$0 != 0}))
        let iviv=try sinfField(sinf,"iviv")
        var priv=try sinfField(sinf,"priv")
        if priv.count == 440 {
            try require(priv.suffix(8).allSatisfy{$0 == 0}, "Invalid 440-byte SINF record trailer")
            priv=Data(priv.prefix(432))
        }
        try require((priv.count == 432 || priv.count == 448) && iviv.count == 16, "Unsupported SINF dimensions")
        let iv=Data(Insecure.MD5.hash(data:nameValue+iviv))
        let derivedKey=Data(credential.map{$0 ^ 0x30})
        let clear=try aes(priv,key:derivedKey,iv:iv,decrypt:true)
        try require(try bytes(clear,0,4) == Data("itun".utf8)
                    && bytes(clear,20,4) == Data("key ".utf8)
                    && bytes(clear,44,4) == Data("iviv".utf8),
                    "Wrong account credential for this IPA")
        return try bytes(clear,24,16)
    }

    private static func supfRecordStart(_ supf:Data, pages:Int, subtype:UInt32) throws -> Int {
        try require(supf.count >= 12, "SUPF record too short")
        let version=supf[0]
        let build=String(data:try bytes(supf,1,3),encoding:.ascii) ?? ""
        try require((version==3 || version==5) && ["507","510","612"].contains(build), "Unsupported SUPF version/build")
        let headerSize=version==3 ? 32 : 12
        let n=Int(try u32(supf,8,big:true))
        try require(n>0 && n<=16, "Invalid SUPF architecture table")
        var pos=12
        for _ in 0..<n {
            try require(pos+4+headerSize <= supf.count, "Truncated SUPF architecture header")
            let length=Int(try u32(supf,pos,big:true))
            let cpu=try u32(supf,pos+4,big:true)
            let sub=try u32(supf,pos+8,big:true)
            try require(length >= headerSize && length <= supf.count-pos-4, "Invalid SUPF architecture length")
            let count=Int(try u32(supf,pos+headerSize,big:true))
            if cpu==arm64 && sub==subtype {
                try require(count>=pages && length >= headerSize+count*32, "Missing SUPF encrypted page records")
                return pos+4+headerSize
            }
            pos+=length+4
        }
        throw DecryptionFailure.invalid("No matching arm64 SUPF slice")
    }
    private static func blockWords(_ bytes:Data, work:Data) throws -> [UInt16] {
        let block=try aes(bytes,key:work,decrypt:false)
        return (0..<8).map { i in UInt16(block[i*2])<<8 | UInt16(block[i*2+1]) }
    }
    private static func xorWords(_ a:[UInt16],_ b:[UInt16]) -> [UInt16] {
        zip(a,b).map{$0 ^ $1}
    }
    private static func finish(_ input:[UInt16]) -> [UInt16] {
        var src=input
        for pairs in roundSelectors {
            var dst:[UInt16]=[]
            for (pair,constant) in zip(pairs,roundConstants) {
                let mixed=UInt64(src[pair.0])+UInt64(src[pair.1])
                let sq=mixed*mixed
                let x=(sq & 0xffffffff) ^ (mixed>>16) ^ constant
                dst.append(UInt16(truncatingIfNeeded:x))
                dst.append(UInt16(truncatingIfNeeded:x>>16))
            }
            src=dst
        }
        var dst:[UInt16]=[]
        for (indices,constant) in zip(finalSelectors,finalConstants) {
            let a=(UInt32(src[indices.1])<<16) | UInt32(src[indices.0])
            let b=(UInt32(src[indices.3])<<16) | UInt32(src[indices.2])
            let sum=a &+ b
            let square=UInt64(sum)*UInt64(sum)
            let x=(square & 0xffffffff) ^ (square>>32) ^ constant
            dst.append(UInt16(truncatingIfNeeded:x))
            dst.append(UInt16(truncatingIfNeeded:x>>16))
        }
        return xorWords(input,dst)
    }
    private static func pageKey(_ wrapped:Data, absoluteIndex:Int, work:Data) throws -> Data {
        try require(wrapped.count==16 && absoluteIndex>=0 && UInt64(absoluteIndex)<UInt64(UInt32.max), "Invalid wrapped FairPlay page")
        let offset=UInt64(absoluteIndex)<<12
        var offsetBytes=Data(count:8)
        for i in 0..<8 {offsetBytes[i]=UInt8(truncatingIfNeeded:offset>>(UInt64(7-i)*8))}
        let a=try blockWords(bytes(wrapped,8,8)+offsetBytes,work:work)
        let b=try blockWords(wrapped,work:work)
        let c=try blockWords(offsetBytes+bytes(wrapped,0,8),work:work)
        let words=finish(xorWords(finish(xorWords(finish(a),b)),c))
        var result=Data()
        for word in words {result.append(UInt8(word>>8));result.append(UInt8(truncatingIfNeeded:word))}
        return result
    }

    static func decrypt(binary:Data, sinf:Data, supf:Data, credential:Data) throws -> (Data,Int) {
        let infos=try encryptionSlices(in:binary)
        try require(!infos.isEmpty, "Executable is not FairPlay-encrypted")
        let work=try deriveWork(credential,sinf)
        var result=binary
        var pageCount=0
        for info in infos {
            let count=info.cryptsize/pageSize
            let recordStart=try supfRecordStart(supf,pages:count,subtype:info.subtype)
            for localPage in 0..<count {
                let record=try bytes(supf,recordStart+32*localPage,32)
                let absolute=(info.base+info.cryptoff)/pageSize+localPage
                let key=try pageKey(bytes(record,0,16),absoluteIndex:absolute,work:work)
                let iv=try bytes(record,16,16)
                let start=info.base+info.cryptoff+pageSize*localPage
                let plaintext=try aes(bytes(binary,start,pageSize),key:key,iv:iv,decrypt:true)
                try require(plaintext != bytes(binary,start,pageSize), "Decryption did not change encrypted pages")
                result.replaceSubrange(start..<(start+pageSize),with:plaintext)
                pageCount+=1
            }
            replaceU32LE(&result,info.cryptidOffset,0)
        }
        try require(try encryptionSlices(in:result).isEmpty, "Encrypted Mach-O remains after decryption")
        return (result,pageCount)
    }
}

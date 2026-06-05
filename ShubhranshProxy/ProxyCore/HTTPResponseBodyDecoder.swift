//
//  HTTPResponseBodyDecoder.swift
//  ShubhranshProxy — ProxyCore
//  Created by Shubhransh Gupta
//
//  Decompresses gzip/deflate bodies for the traffic inspector (Proxyman-style display).
//

import Foundation
import zlib

enum HTTPResponseBodyDecoder {
    static func decodedBody(headerBlock: String?, body: Data) -> Data {
        guard !body.isEmpty else { return body }
        let encoding = contentEncoding(from: headerBlock)
        switch encoding {
        case .gzip:
            return gunzip(body) ?? body
        case .deflate:
            return inflateDeflate(body) ?? body
        case .identity, .none:
            return maybeGunzipByMagic(body)
        }
    }

    private enum ContentEncoding {
        case none
        case identity
        case gzip
        case deflate
    }

    private static func contentEncoding(from headerBlock: String?) -> ContentEncoding {
        guard let headerBlock else { return .none }
        for line in headerBlock.split(separator: "\r\n") {
            let lower = line.lowercased()
            guard lower.hasPrefix("content-encoding:") else { continue }
            let value = line.split(separator: ":", maxSplits: 1).last?
                .trimmingCharacters(in: .whitespaces).lowercased() ?? ""
            if value.contains("gzip") || value.contains("x-gzip") { return .gzip }
            if value.contains("deflate") { return .deflate }
            if value.contains("identity") { return .identity }
        }
        return .none
    }

    private static func maybeGunzipByMagic(_ body: Data) -> Data {
        guard body.count >= 2, body[body.startIndex] == 0x1F, body[body.startIndex + 1] == 0x8B else {
            return body
        }
        return gunzip(body) ?? body
    }

    private static func gunzip(_ data: Data) -> Data? {
        decompress(data, windowBits: MAX_WBITS + 32)
    }

    private static func inflateDeflate(_ data: Data) -> Data? {
        decompress(data, windowBits: MAX_WBITS)
    }

    private static func decompress(_ data: Data, windowBits: Int32) -> Data? {
        guard !data.isEmpty else { return nil }

        return data.withUnsafeBytes { inputBuffer -> Data? in
            guard let inputBase = inputBuffer.baseAddress?.assumingMemoryBound(to: Bytef.self) else {
                return nil
            }

            var stream = z_stream()
            stream.next_in = UnsafeMutablePointer<Bytef>(mutating: inputBase)
            stream.avail_in = uInt(data.count)

            guard inflateInit2_(&stream, windowBits, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
                return nil
            }
            defer { inflateEnd(&stream) }

            var output = Data()
            let chunkSize = 32_768
            var status: Int32 = Z_OK

            repeat {
                var chunk = [UInt8](repeating: 0, count: chunkSize)
                let produced: Int = chunk.withUnsafeMutableBytes { outputBuffer in
                    guard let outBase = outputBuffer.baseAddress?.assumingMemoryBound(to: Bytef.self) else {
                        return -1
                    }
                    stream.next_out = outBase
                    stream.avail_out = uInt(chunkSize)
                    status = inflate(&stream, Z_NO_FLUSH)
                    if status != Z_OK && status != Z_STREAM_END && status != Z_BUF_ERROR {
                        return -1
                    }
                    return chunkSize - Int(stream.avail_out)
                }
                if produced < 0 { return nil }
                if produced > 0 {
                    output.append(chunk, count: produced)
                }
            } while status == Z_OK

            guard status == Z_STREAM_END, !output.isEmpty else { return nil }
            return output
        }
    }
}

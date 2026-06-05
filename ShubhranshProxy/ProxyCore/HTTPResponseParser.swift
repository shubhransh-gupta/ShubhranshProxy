//
//  HTTPResponseParser.swift
//  ShubhranshProxy — ProxyCore
//  Created by Shubhransh Gupta
//
//  Minimal HTTP/1.x response framing for the traffic inspector (not a general client).
//

import Foundation

struct ParsedHTTPResponse: Sendable {
    var statusCode: Int
    var statusLine: String
    var headerBlock: String
    var body: Data
}

enum HTTPResponseParseError: Error, Sendable {
    case invalidStatusLine
    case headerTooLarge
}

/// Incrementally collects upstream bytes and yields complete HTTP/1.x response messages.
struct HTTPResponseStreamBuffer {
    private static let headerTerminator = Data([0x0D, 0x0A, 0x0D, 0x0A])
    private var buffer = Data()

    mutating func append(_ chunk: Data) {
        buffer.append(chunk)
    }

    mutating func popCompleteResponse(connectionClosed: Bool = false) -> Data? {
        guard !buffer.isEmpty else { return nil }

        guard let sep = buffer.range(of: Self.headerTerminator) else {
            return connectionClosed ? drainAll() : nil
        }

        let headerText = String(decoding: buffer.subdata(in: buffer.startIndex..<sep.upperBound), as: UTF8.self)
        let lines = headerText.split(separator: "\r\n", omittingEmptySubsequences: false)
        guard let statusLine = lines.first, statusLine.hasPrefix("HTTP/") else {
            return connectionClosed ? drainAll() : nil
        }

        var contentLength: Int?
        var transferChunked = false
        for line in lines.dropFirst() {
            if line.isEmpty { break }
            let lower = line.lowercased()
            if lower.hasPrefix("content-length:") {
                let value = line.drop { $0 != ":" }.dropFirst().trimmingCharacters(in: .whitespaces)
                contentLength = Int(value)
            }
            if lower.hasPrefix("transfer-encoding:"), lower.contains("chunked") {
                transferChunked = true
            }
        }

        let bodyStart = sep.upperBound
        let bodyOffset = buffer.distance(from: buffer.startIndex, to: bodyStart)

        if transferChunked {
            let encodedBody = buffer.subdata(in: bodyStart..<buffer.endIndex)
            guard let encodedLength = HTTPResponseParser.chunkedEncodedByteCount(encodedBody) else {
                return connectionClosed ? drainAll() : nil
            }
            let totalLength = bodyOffset + encodedLength
            return extractMessage(length: totalLength)
        }

        if let contentLength {
            let totalLength = bodyOffset + contentLength
            guard buffer.count >= totalLength else {
                return connectionClosed ? drainAll() : nil
            }
            return extractMessage(length: totalLength)
        }

        if connectionClosed {
            return drainAll()
        }
        return nil
    }

    mutating func popAllCompleteResponses(connectionClosed: Bool) -> [Data] {
        var messages: [Data] = []
        while let message = popCompleteResponse(connectionClosed: connectionClosed) {
            messages.append(message)
        }
        return messages
    }

    var isEmpty: Bool { buffer.isEmpty }

    mutating func drainRemaining() -> Data {
        let all = buffer
        buffer = Data()
        return all
    }

    private mutating func extractMessage(length: Int) -> Data {
        let end = buffer.startIndex + length
        let message = buffer.subdata(in: buffer.startIndex..<end)
        buffer.removeSubrange(buffer.startIndex..<end)
        return message
    }

    private mutating func drainAll() -> Data {
        let all = buffer
        buffer = Data()
        return all
    }
}

enum HTTPResponseParser {
    private static let maxHeaderBytes = 512 * 1024
    private static let crlf = Data([0x0D, 0x0A])
    private static let headerTerminator = Data([0x0D, 0x0A, 0x0D, 0x0A])

    /// Parses a single complete response buffer (headers + body per Content-Length or decoded chunked body).
    static func parse(raw: Data) throws -> ParsedHTTPResponse {
        guard raw.count <= 64 * 1024 * 1024 else {
            return ParsedHTTPResponse(statusCode: 0, statusLine: "", headerBlock: "", body: raw)
        }
        guard let sep = raw.range(of: headerTerminator) else {
            return ParsedHTTPResponse(statusCode: 0, statusLine: "", headerBlock: "", body: raw)
        }
        let headerSize = sep.upperBound - raw.startIndex
        if headerSize > maxHeaderBytes { throw HTTPResponseParseError.headerTooLarge }

        let headerData = raw.subdata(in: raw.startIndex..<sep.upperBound)
        let headerText = String(decoding: headerData, as: UTF8.self)
        let lines = headerText.split(separator: "\r\n", omittingEmptySubsequences: false)
        guard let statusLine = lines.first else { throw HTTPResponseParseError.invalidStatusLine }
        let statusParts = statusLine.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard statusParts.count >= 2, let code = Int(statusParts[1]) else { throw HTTPResponseParseError.invalidStatusLine }

        var contentLength: Int?
        var transferChunked = false
        for line in lines.dropFirst() {
            if line.isEmpty { break }
            let lower = line.lowercased()
            if lower.hasPrefix("content-length:") {
                let value = line.drop { $0 != ":" }.dropFirst().trimmingCharacters(in: .whitespaces)
                contentLength = Int(value)
            }
            if lower.hasPrefix("transfer-encoding:"), lower.contains("chunked") {
                transferChunked = true
            }
        }

        let bodyStart = sep.upperBound
        let rest = raw.subdata(in: bodyStart..<raw.endIndex)
        if transferChunked, let decoded = decodeChunkedBody(rest) {
            return ParsedHTTPResponse(
                statusCode: code,
                statusLine: String(statusLine),
                headerBlock: headerText,
                body: decoded
            )
        }
        if let contentLength, rest.count >= contentLength {
            return ParsedHTTPResponse(
                statusCode: code,
                statusLine: String(statusLine),
                headerBlock: headerText,
                body: rest.subdata(in: 0..<contentLength)
            )
        }
        return ParsedHTTPResponse(
            statusCode: code,
            statusLine: String(statusLine),
            headerBlock: headerText,
            body: rest
        )
    }

    static func chunkedEncodedByteCount(_ encoded: Data) -> Int? {
        var index = encoded.startIndex
        while index < encoded.endIndex {
            guard let lineEnd = encoded[index...].range(of: crlf) else { return nil }
            let sizeLine = encoded.subdata(in: index..<lineEnd.lowerBound)
            let sizeToken = String(decoding: sizeLine, as: UTF8.self)
                .split(separator: ";", maxSplits: 1).first ?? ""
            guard let chunkSize = Int(sizeToken.trimmingCharacters(in: .whitespaces), radix: 16) else {
                return nil
            }
            index = lineEnd.upperBound

            if chunkSize == 0 {
                if let trailerEnd = encoded[index...].range(of: headerTerminator) {
                    return trailerEnd.upperBound - encoded.startIndex
                }
                if index + crlf.count <= encoded.endIndex,
                   encoded[index] == 0x0D, encoded[index + 1] == 0x0A {
                    return index + crlf.count - encoded.startIndex
                }
                return nil
            }

            index += chunkSize
            guard index + crlf.count <= encoded.endIndex else { return nil }
            index += crlf.count
        }
        return nil
    }

    static func decodeChunkedBody(_ encoded: Data) -> Data? {
        var index = encoded.startIndex
        var decoded = Data()

        while index < encoded.endIndex {
            guard let lineEnd = encoded[index...].range(of: crlf) else { return nil }
            let sizeLine = encoded.subdata(in: index..<lineEnd.lowerBound)
            let sizeToken = String(decoding: sizeLine, as: UTF8.self)
                .split(separator: ";", maxSplits: 1).first ?? ""
            guard let chunkSize = Int(sizeToken.trimmingCharacters(in: .whitespaces), radix: 16) else {
                return nil
            }
            index = lineEnd.upperBound

            if chunkSize == 0 {
                return decoded
            }

            guard index + chunkSize <= encoded.endIndex else { return nil }
            decoded.append(encoded.subdata(in: index..<(index + chunkSize)))
            index += chunkSize
            guard index + crlf.count <= encoded.endIndex else { return nil }
            index += crlf.count
        }

        return nil
    }
}

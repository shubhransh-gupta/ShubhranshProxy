//
//  RawHTTPRequestParse.swift
//  ShubhranshProxy — ProxyCore
//  Created by Shubhransh Gupta
//
//  Minimal HTTP/1.1 request framing for a forward proxy: captures the first
//  request on a connection as raw bytes so we can replay it to the origin.
//  Chunked request bodies are not supported in this first iteration.
//

import Foundation

enum RawHTTPParseError: Error, Sendable {
    case invalidRequestLine
    case missingHost
    case invalidContentLength
    case unsupportedTransferEncoding
}

/// Parsed metadata plus the exact byte range to forward to the origin (verbatim).
struct ParsedInboundRequest: Sendable {
    /// Full request bytes (headers + optional body) to send upstream.
    var raw: Data
    var method: String
    /// For CONNECT, authority is "host:port". For plain HTTP, may be absolute URL or path.
    var target: String
    var isConnect: Bool
}

enum RawHTTPRequestParse {
    /// Returns `nil` if the buffer does not yet contain a full request.
    static func parseIfComplete(buffer: inout Data) throws -> ParsedInboundRequest? {
        guard let headerEnd = buffer.range(of: Data([0x0D, 0x0A, 0x0D, 0x0A])) else {
            return nil
        }
        let headerData = buffer.subdata(in: buffer.startIndex..<headerEnd.upperBound)
        let headerString = String(decoding: headerData, as: UTF8.self)
        let lines = headerString.split(separator: "\r\n", omittingEmptySubsequences: false)
        guard let first = lines.first else { throw RawHTTPParseError.invalidRequestLine }
        let parts = first.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard parts.count == 3 else { throw RawHTTPParseError.invalidRequestLine }
        let method = String(parts[0])
        let target = String(parts[1])

        if method.caseInsensitiveCompare("CONNECT") == .orderedSame {
            let request = ParsedInboundRequest(
                raw: headerData,
                method: method,
                target: target,
                isConnect: true
            )
            buffer.removeSubrange(buffer.startIndex..<headerEnd.upperBound)
            return request
        }

        var contentLength: Int?
        var transferEncodingChunked = false
        for line in lines.dropFirst() {
            if line.isEmpty { break }
            let lower = line.lowercased()
            if lower.hasPrefix("content-length:") {
                let value = line.drop { $0 != ":" }.dropFirst().trimmingCharacters(in: .whitespaces)
                guard let n = Int(value) else { throw RawHTTPParseError.invalidContentLength }
                contentLength = n
            }
            if lower.hasPrefix("transfer-encoding:") {
                let value = line.drop { $0 != ":" }.dropFirst().lowercased()
                if value.contains("chunked") { transferEncodingChunked = true }
            }
        }
        if transferEncodingChunked { throw RawHTTPParseError.unsupportedTransferEncoding }

        let bodyStart = headerEnd.upperBound
        let totalNeeded = bodyStart + (contentLength ?? 0)
        guard buffer.count >= totalNeeded else { return nil }

        let full = buffer.subdata(in: buffer.startIndex..<totalNeeded)
        buffer.removeSubrange(buffer.startIndex..<totalNeeded)
        return ParsedInboundRequest(
            raw: full,
            method: method,
            target: target,
            isConnect: false
        )
    }
}

/// Resolves `host` and `port` for a plain HTTP proxy request (non-CONNECT).
enum HTTPProxyTargetResolver {
    static func hostPort(for request: ParsedInboundRequest) throws -> (host: String, port: Int) {
        if request.isConnect {
            return try parseAuthority(request.target, defaultPort: 443)
        }
        // Absolute-form: GET http://host/path HTTP/1.1
        if let url = URL(string: request.target), let host = url.host {
            let port = url.port ?? (url.scheme?.lowercased() == "https" ? 443 : 80)
            return (host, port)
        }
        // Origin-form — require Host header
        let header = String(decoding: request.raw, as: UTF8.self)
        guard let hostLine = header.split(separator: "\r\n").first(where: {
            $0.split(separator: ":", maxSplits: 1).first?.lowercased() == "host"
        }) else { throw RawHTTPParseError.missingHost }
        let value = hostLine.split(separator: ":", maxSplits: 1).last.map(String.init) ?? ""
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        return try parseAuthority(trimmed, defaultPort: 80)
    }

    /// `defaultPort` is used when the authority omits a port (`CONNECT` → 443, `Host` → 80).
    private static func parseAuthority(_ authority: String, defaultPort: Int) throws -> (host: String, port: Int) {
        if authority.hasPrefix("[") {
            guard let endBracket = authority.lastIndex(of: "]") else { throw RawHTTPParseError.missingHost }
            let inner = authority.index(after: authority.startIndex)
            let host = String(authority[inner..<endBracket])
            var idx = authority.index(after: endBracket)
            if idx < authority.endIndex, authority[idx] == ":" {
                idx = authority.index(after: idx)
                let portStr = String(authority[idx...])
                guard let p = Int(portStr) else { throw RawHTTPParseError.missingHost }
                return (host, p)
            }
            return (host, defaultPort)
        }
        let parts = authority.split(separator: ":", omittingEmptySubsequences: false)
        if parts.count >= 2, let p = Int(parts.last!) {
            let host = parts.dropLast().joined(separator: ":")
            return (String(host), p)
        }
        return (authority, defaultPort)
    }
}

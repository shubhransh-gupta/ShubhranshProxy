//
//  HTTPOutboundRequestNormalizer.swift
//  ShubhranshProxy — ProxyCore
//  Created by Shubhransh Gupta
//
//  Prepares outbound proxy requests so responses are inspectable (Charles/Proxyman style):
//  force Connection: close and strip Accept-Encoding so origins return plain JSON/text.
//

import Foundation

enum HTTPOutboundRequestNormalizer {
    private static let headerTerminator = Data([0x0D, 0x0A, 0x0D, 0x0A])

    /// Rewrites request headers before forwarding to the origin.
    static func apply(to raw: Data) -> Data {
        guard let range = raw.range(of: headerTerminator) else { return raw }
        let headerRegion = raw.subdata(in: raw.startIndex..<range.lowerBound)
        let headerText = String(decoding: headerRegion, as: UTF8.self)
        let lines = headerText.split(separator: "\r\n", omittingEmptySubsequences: false)
        guard !lines.isEmpty else { return raw }

        var outLines: [String] = [String(lines[0])]
        var sawConnection = false
        var sawAcceptEncoding = false

        for line in lines.dropFirst() {
            if line.isEmpty { break }
            let name = line.split(separator: ":", maxSplits: 1).first?
                .trimmingCharacters(in: .whitespaces).lowercased() ?? ""
            switch name {
            case "connection":
                outLines.append("Connection: close")
                sawConnection = true
            case "accept-encoding":
                sawAcceptEncoding = true
            default:
                outLines.append(String(line))
            }
        }

        if !sawConnection {
            outLines.insert("Connection: close", at: 1)
        }
        if !sawAcceptEncoding {
            outLines.insert("Accept-Encoding: identity", at: min(1, outLines.count))
        }

        let newHeader = outLines.joined(separator: "\r\n") + "\r\n\r\n"
        let body = raw.subdata(in: range.upperBound..<raw.endIndex)
        return Data(newHeader.utf8) + body
    }
}

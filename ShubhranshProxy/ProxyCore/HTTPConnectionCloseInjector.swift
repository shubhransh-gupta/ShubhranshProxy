//
//  HTTPConnectionCloseInjector.swift
//  ShubhranshProxy — ProxyCore
//  Created by Shubhransh Gupta
//
//  Ensures the origin closes after one response so this MVP can reuse the client
//  channel for the next pipelined request without an HTTP response parser.
//

import Foundation

enum HTTPConnectionCloseInjector {
    /// Inserts or replaces `Connection: close` before the header terminator.
    static func apply(to raw: Data) -> Data {
        guard let range = raw.range(of: Data([0x0D, 0x0A, 0x0D, 0x0A])) else { return raw }
        let headerRegion = raw.subdata(in: raw.startIndex..<range.lowerBound)
        let headerText = String(decoding: headerRegion, as: UTF8.self)
        let lines = headerText.split(separator: "\r\n", omittingEmptySubsequences: false)
        guard !lines.isEmpty else { return raw }

        var outLines: [String] = lines.map(String.init)
        var replaced = false
        for i in outLines.indices.dropFirst() {
            let line = outLines[i]
            if line.split(separator: ":", maxSplits: 1).first?.trimmingCharacters(in: .whitespaces).lowercased() == "connection" {
                outLines[i] = "Connection: close"
                replaced = true
                break
            }
        }
        if !replaced {
            outLines.insert("Connection: close", at: 1)
        }
        let newHeader = outLines.joined(separator: "\r\n") + "\r\n\r\n"
        let body = raw.subdata(in: range.upperBound..<raw.endIndex)
        return Data(newHeader.utf8) + body
    }
}

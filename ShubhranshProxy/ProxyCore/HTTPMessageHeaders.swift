//
//  HTTPMessageHeaders.swift
//  ShubhranshProxy — ProxyCore
//  Created by Shubhransh Gupta
//

import Foundation

enum HTTPMessageHeaders {
    /// Returns the raw header block (including status or request line) as a single string.
    static func headerBlock(from message: Data) -> String {
        guard let r = message.range(of: Data([0x0D, 0x0A, 0x0D, 0x0A])) else {
            return String(decoding: message.prefix(8192), as: UTF8.self)
        }
        return String(decoding: message.subdata(in: message.startIndex..<r.upperBound), as: UTF8.self)
    }

    static func requestBody(from message: Data) -> Data {
        guard let r = message.range(of: Data([0x0D, 0x0A, 0x0D, 0x0A])) else { return Data() }
        return message.subdata(in: r.upperBound..<message.endIndex)
    }
}

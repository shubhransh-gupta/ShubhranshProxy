//
//  ClientAddressResolver.swift
//  ShubhranshProxy — ProxyCore
//
//  Created by Shubhransh Gupta
//

import Foundation
import NIOCore

enum ClientAddressResolver {
    static func ipAddress(for channel: Channel) -> String? {
        guard let address = channel.remoteAddress else { return nil }
        switch address {
        case .v4(let v4):
            return normalize(v4.host)
        case .v6(let v6):
            return normalize(v6.host)
        default:
            return nil
        }
    }

    static func normalize(_ ip: String?) -> String? {
        guard var value = ip?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        if value.hasPrefix("::ffff:") {
            value = String(value.dropFirst("::ffff:".count))
        }
        if let zoneIndex = value.firstIndex(of: "%") {
            value = String(value[..<zoneIndex])
        }
        return value
    }

    static func isLoopback(_ ip: String?) -> Bool {
        guard let normalized = normalize(ip)?.lowercased() else { return true }
        if normalized == "127.0.0.1" || normalized == "::1" || normalized == "0:0:0:0:0:0:0:1" {
            return true
        }
        return normalized.hasPrefix("127.")
    }

    static func isPrivateLAN(_ ip: String?) -> Bool {
        guard let normalized = normalize(ip) else { return false }
        let parts = normalized.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else { return false }
        switch parts[0] {
        case 10:
            return true
        case 172 where (16...31).contains(parts[1]):
            return true
        case 192 where parts[1] == 168:
            return true
        default:
            return false
        }
    }
}

//
//  PreferredDecryptHosts.swift
//  ShubhranshProxy — Core
//
//  Created by Shubhransh Gupta
//

import Foundation

/// Domains the user wants decrypted on Mac by default (persisted across launches).
enum PreferredDecryptHosts {
    static let migrationKey = "ShubhranshProxy.ssl.preferredDecryptHosts.v1"

    static let hosts: [String] = [
        "api-gateway.juno.lenskart.com",
        "api-gateway.juno.preprod.lenskart.com",
    ]

    static func merge(into settings: inout SSLProxySettings) -> Bool {
        var changed = false
        for host in hosts {
            let normalized = host.lowercased()
            let exists = settings.includedHosts.contains {
                $0.caseInsensitiveCompare(normalized) == .orderedSame
            }
            if !exists {
                settings.includedHosts.append(normalized)
                changed = true
            }
        }
        return changed
    }
}

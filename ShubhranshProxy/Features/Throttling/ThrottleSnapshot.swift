//
//  ThrottleSnapshot.swift — Phase 4
//
//  Created by Shubhransh Gupta

import Foundation

struct ThrottleSnapshot: Sendable, Equatable, Codable {
    var isEnabled = false
    var bytesPerSecond: Int = 0
    var latencyMs: Int = 0

    static let off = ThrottleSnapshot(isEnabled: false, bytesPerSecond: 0, latencyMs: 0)

    static func profile(_ profile: ThrottleProfileStore.Profile, customBytesPerSecond: Int = 50_000) -> ThrottleSnapshot {
        switch profile {
        case .off:
            return .off
        case .slow3G:
            return ThrottleSnapshot(isEnabled: true, bytesPerSecond: 780 * 1024 / 8, latencyMs: 2000)
        case .fast3G:
            return ThrottleSnapshot(isEnabled: true, bytesPerSecond: 1_600 * 1024 / 8, latencyMs: 562)
        case .lte:
            return ThrottleSnapshot(isEnabled: true, bytesPerSecond: 12_000 * 1024 / 8, latencyMs: 70)
        case .custom:
            return ThrottleSnapshot(isEnabled: true, bytesPerSecond: max(1024, customBytesPerSecond), latencyMs: 0)
        }
    }
}

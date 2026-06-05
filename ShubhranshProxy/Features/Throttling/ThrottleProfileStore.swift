//
//  ThrottleProfileStore.swift — Phase 4
//
//  Created by Shubhransh Gupta

import Foundation

@MainActor
@Observable
final class ThrottleProfileStore {
    enum Profile: String, CaseIterable, Identifiable, Codable {
        case off, slow3G, fast3G, lte, custom
        var id: String { rawValue }
        var label: String {
            switch self {
            case .off: "Off"
            case .slow3G: "Slow 3G (~780 Kbps, 2s latency)"
            case .fast3G: "Fast 3G (~1.6 Mbps, 562ms latency)"
            case .lte: "LTE (~12 Mbps, 70ms latency)"
            case .custom: "Custom bandwidth"
            }
        }
    }

    var selected: Profile = .off
    var customBytesPerSecond = 50_000

    var snapshot: ThrottleSnapshot {
        ThrottleSnapshot.profile(selected, customBytesPerSecond: customBytesPerSecond)
    }
}

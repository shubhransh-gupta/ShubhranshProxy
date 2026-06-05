//
//  MapRemoteModels.swift
//  ShubhranshProxy — MappingEngine
//  Created by Shubhransh Gupta
//

import Foundation

struct MapRemoteRuleSnapshot: Sendable, Codable, Identifiable {
    var id: UUID
    /// Matches the full request URL (plain text or regex).
    var sourcePattern: String
    /// Replacement base URL or regex replacement (e.g. https://staging.api.com).
    var destinationPattern: String
    var isEnabled: Bool
}

struct MapRemoteRule: Identifiable, Hashable, Codable {
    var id: UUID
    var sourcePattern: String
    var destinationPattern: String
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        sourcePattern: String = "",
        destinationPattern: String = "",
        isEnabled: Bool = true
    ) {
        self.id = id
        self.sourcePattern = sourcePattern
        self.destinationPattern = destinationPattern
        self.isEnabled = isEnabled
    }

    var snapshot: MapRemoteRuleSnapshot {
        MapRemoteRuleSnapshot(
            id: id,
            sourcePattern: sourcePattern,
            destinationPattern: destinationPattern,
            isEnabled: isEnabled
        )
    }
}

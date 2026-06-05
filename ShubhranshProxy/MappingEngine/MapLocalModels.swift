//
//  MapLocalModels.swift
//  ShubhranshProxy — MappingEngine
//
//  Created by Shubhransh Gupta
//

import Foundation

/// Serializable snapshot of a Map Local rule for use on NIO threads.
struct MapLocalRuleSnapshot: Sendable, Codable, Identifiable {
    var id: UUID
    var pattern: String
    var localFilePath: String?
    var inlineBody: String?
    var contentType: String?
    var isEnabled: Bool

    var usesInlineBody: Bool {
        guard let inlineBody else { return false }
        return !inlineBody.isEmpty
    }
}

/// A single Map Local rule (no artificial caps).
struct MapLocalRule: Identifiable, Hashable, Codable {
    var id: UUID
    /// Regex tested against the full request URL string.
    var pattern: String
    /// Local file whose bytes replace the origin response body when the rule matches.
    var localFileURL: URL?
    /// Inline response body (JSON, HTML, text). Takes precedence over file when non-empty.
    var inlineBody: String
    var contentType: String
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        pattern: String,
        localFileURL: URL? = nil,
        inlineBody: String = "",
        contentType: String = "application/json; charset=utf-8",
        isEnabled: Bool = true
    ) {
        self.id = id
        self.pattern = pattern
        self.localFileURL = localFileURL
        self.inlineBody = inlineBody
        self.contentType = contentType
        self.isEnabled = isEnabled
    }

    var usesInlineBody: Bool {
        !inlineBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var snapshot: MapLocalRuleSnapshot {
        MapLocalRuleSnapshot(
            id: id,
            pattern: pattern,
            localFilePath: localFileURL?.path,
            inlineBody: usesInlineBody ? inlineBody : nil,
            contentType: usesInlineBody ? contentType : nil,
            isEnabled: isEnabled
        )
    }
}

//
//  GraphQLInspector.swift
//  ShubhranshProxy — Features (Phase 5)
//  Created by Shubhransh Gupta
//

import Foundation

/// GraphQL operation parsing — scaffold for Phase 5.
enum GraphQLInspector {
    static func parseOperation(from body: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let query = json["query"] as? String else { return nil }
        return query
    }

    static let phaseStatus = "Full GraphQL inspector ships in Phase 5."
}

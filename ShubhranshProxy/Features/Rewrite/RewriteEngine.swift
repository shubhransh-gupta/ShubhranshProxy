//
//  RewriteEngine.swift — Phase 4
//
//  Created by Shubhransh Gupta

import Foundation

@MainActor
@Observable
final class RewriteEngine {
    var rules: [RewriteRuleSnapshot] = []

    var status: String {
        rules.isEmpty
            ? "Add regex rewrite rules for request/response headers and bodies."
            : "\(rules.filter(\.isEnabled).count) active rewrite rule(s)."
    }

    func addRule() {
        rules.append(RewriteRuleSnapshot(name: "New rule"))
    }

    func remove(at offsets: IndexSet) {
        for index in offsets.sorted(by: >) {
            rules.remove(at: index)
        }
    }
}

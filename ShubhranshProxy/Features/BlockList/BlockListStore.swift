//
//  BlockListStore.swift — Phase 4
//
//  Created by Shubhransh Gupta

import Foundation

@MainActor
@Observable
final class BlockListStore {
    var isEnabled = false
    var domainPatterns: [String] = []
    var pathPatterns: [String] = []

    var snapshot: BlockListSnapshot {
        BlockListSnapshot(isEnabled: isEnabled, domainPatterns: domainPatterns, pathPatterns: pathPatterns)
    }

    func addDomainPattern() { domainPatterns.append("") }
    func addPathPattern() { pathPatterns.append("") }

    func removeDomain(at offsets: IndexSet) {
        for i in offsets.sorted(by: >) { domainPatterns.remove(at: i) }
    }

    func removePath(at offsets: IndexSet) {
        for i in offsets.sorted(by: >) { pathPatterns.remove(at: i) }
    }
}

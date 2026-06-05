//
//  FeatureMailboxes.swift — Phase 4
//
//  Created by Shubhransh Gupta

import Foundation

final class BlockListMailbox: @unchecked Sendable {
    private let lock = NSLock()
    private var value = BlockListSnapshot()

    func replace(_ snapshot: BlockListSnapshot) {
        lock.lock()
        value = snapshot
        lock.unlock()
    }

    func current() -> BlockListSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

final class RewriteRulesMailbox: @unchecked Sendable {
    private let lock = NSLock()
    private var rules: [RewriteRuleSnapshot] = []
    private var enabled = false

    func replace(rules: [RewriteRuleSnapshot], enabled: Bool) {
        lock.lock()
        self.rules = rules
        self.enabled = enabled
        lock.unlock()
    }

    func currentRules() -> [RewriteRuleSnapshot] {
        lock.lock()
        defer { lock.unlock() }
        return rules
    }

    func isEnabled() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return enabled
    }
}

final class ThrottleMailbox: @unchecked Sendable {
    private let lock = NSLock()
    private var value = ThrottleSnapshot.off

    func replace(_ snapshot: ThrottleSnapshot) {
        lock.lock()
        value = snapshot
        lock.unlock()
    }

    func current() -> ThrottleSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

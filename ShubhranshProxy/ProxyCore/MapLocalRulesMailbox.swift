//
//  MapLocalRulesMailbox.swift
//  ShubhranshProxy — ProxyCore
//  Created by Shubhransh Gupta
//
//  Lock-protected copy of Map Local rules readable from NIO event loops without MainActor.
//

import Foundation

/// Thread-safe snapshot for `ProxyRuntimeCallbacks.mapLocalRules`.
final class MapLocalRulesMailbox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: [MapLocalRuleSnapshot] = []

    func replace(_ rules: [MapLocalRuleSnapshot]) {
        lock.lock()
        value = rules
        lock.unlock()
    }

    func current() -> [MapLocalRuleSnapshot] {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

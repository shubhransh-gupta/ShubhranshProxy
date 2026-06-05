//
//  MapRemoteRulesMailbox.swift
//  ShubhranshProxy — ProxyCore
//  Created by Shubhransh Gupta
//

import Foundation

final class MapRemoteRulesMailbox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: [MapRemoteRuleSnapshot] = []

    func replace(_ rules: [MapRemoteRuleSnapshot]) {
        lock.lock()
        value = rules
        lock.unlock()
    }

    func current() -> [MapRemoteRuleSnapshot] {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

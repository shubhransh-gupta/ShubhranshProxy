//
//  SSLProxySettingsMailbox.swift
//  ShubhranshProxy — ProxyCore
//  Created by Shubhransh Gupta
//

import Foundation

/// Thread-safe SSL settings readable from NIO event loops.
final class SSLProxySettingsMailbox: @unchecked Sendable {
    private let lock = NSLock()
    private var value = SSLProxySettings()

    func replace(_ settings: SSLProxySettings) {
        lock.lock()
        value = settings
        lock.unlock()
    }

    func current() -> SSLProxySettings {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

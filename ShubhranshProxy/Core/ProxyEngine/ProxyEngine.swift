//
//  ProxyEngine.swift
//  ShubhranshProxy — Core
//  Created by Shubhransh Gupta
//
//  Facade over the NIO HTTP forward proxy (Phase 1). Phase 2+ adds MITM here.
//

import Foundation

/// Local HTTP(S) forward proxy listener.
actor ProxyEngine {
    enum State: Sendable, Equatable {
        case stopped
        case running(host: String, port: Int)
    }

    private let service = HTTPProxyService()
    private(set) var state: State = .stopped

    var isRunning: Bool {
        if case .running = state { return true }
        return false
    }

    func start(configuration: HTTPProxyConfiguration, callbacks: ProxyRuntimeCallbacks) async throws {
        try await service.start(configuration: configuration, callbacks: callbacks)
        state = .running(host: configuration.listenHost, port: configuration.listenPort)
    }

    func stop() async {
        await service.stop()
        state = .stopped
    }
}

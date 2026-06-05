//
//  ReverseProxyEngine.swift
//  ShubhranshProxy — Core (Phase 4)
//  Created by Shubhransh Gupta
//
//  Reverse proxy: expose local listener that forwards to a fixed upstream origin.
//

import Foundation

/// Reverse proxy mode — scaffold for Phase 4.
actor ReverseProxyEngine {
    struct Configuration: Sendable {
        var listenHost: String
        var listenPort: Int
        var upstreamBaseURL: URL
    }

    private(set) var isRunning = false

    func start(configuration: Configuration) async throws {
        throw ReverseProxyError.notImplemented
    }

    func stop() async {
        isRunning = false
    }

    enum ReverseProxyError: Error, LocalizedError {
        case notImplemented
        var errorDescription: String? { "Reverse proxy ships in Phase 4." }
    }
}

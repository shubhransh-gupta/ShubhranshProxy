//
//  SOCKS5ProxyEngine.swift
//  ShubhranshProxy — Core (Phase 4)
//  Created by Shubhransh Gupta
//
//  SOCKS5 listener for apps that require SOCKS instead of HTTP CONNECT.
//

import Foundation

/// SOCKS5 proxy support — scaffold for Phase 4.
actor SOCKS5ProxyEngine {
    enum State: Sendable, Equatable {
        case stopped
        case running(host: String, port: Int)
    }

    private(set) var state: State = .stopped

    func start(host: String, port: Int) async throws {
        throw SOCKS5Error.notImplemented
    }

    func stop() async {
        state = .stopped
    }

    enum SOCKS5Error: Error, LocalizedError {
        case notImplemented
        var errorDescription: String? { "SOCKS5 proxy ships in Phase 4." }
    }
}

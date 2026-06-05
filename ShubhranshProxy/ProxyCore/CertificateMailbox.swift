//
//  CertificateMailbox.swift
//  ShubhranshProxy — ProxyCore
//  Created by Shubhransh Gupta
//

import Foundation

/// PEM material for NIOSSL server termination during MITM.
struct SSLCertificateMaterial: Sendable {
    var certificateChainPEM: String
    var privateKeyPEM: String
}

/// Thread-safe leaf certificate provider for NIO worker threads.
final class CertificateMailbox: @unchecked Sendable {
    private let lock = NSLock()
    private var provider: (@Sendable (String) throws -> SSLCertificateMaterial)?

    func setProvider(_ provider: @escaping @Sendable (String) throws -> SSLCertificateMaterial) {
        lock.lock()
        self.provider = provider
        lock.unlock()
    }

    func leafMaterial(for host: String) throws -> SSLCertificateMaterial {
        lock.lock()
        let provider = self.provider
        lock.unlock()
        guard let provider else {
            throw CertificateMailboxError.providerNotConfigured
        }
        return try provider(host)
    }

    enum CertificateMailboxError: Error, LocalizedError {
        case providerNotConfigured
        var errorDescription: String? { "Root CA is not ready. Install the ShubhranshProxy certificate first." }
    }
}

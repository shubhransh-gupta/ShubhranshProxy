//
//  SynchronousCertificateIssuer.swift
//  ShubhranshProxy — CertificateManager (Phase 2)
//  Created by Shubhransh Gupta
//
//  Lock-protected leaf issuance for NIO worker threads (no actor hop).
//

import Foundation

final class SynchronousCertificateIssuer: @unchecked Sendable {
    private let lock = NSLock()
    private var root: CertificateAuthority.RootMaterial?
    private var cache: [String: SSLCertificateMaterial] = [:]
    private let maxCache = 512

    func installRoot(_ material: CertificateAuthority.RootMaterial) {
        lock.lock()
        root = material
        cache.removeAll(keepingCapacity: true)
        lock.unlock()
    }

    func reloadFromDisk() throws {
        guard let loaded = try CertificateAuthority.loadPersistedRoot() else {
            throw IssuerError.rootMissing
        }
        installRoot(loaded)
    }

    func clear() {
        lock.lock()
        root = nil
        cache.removeAll(keepingCapacity: true)
        lock.unlock()
    }

    func leafMaterial(for host: String) throws -> SSLCertificateMaterial {
        lock.lock()
        defer { lock.unlock() }
        let key = host.lowercased()
        if let cached = cache[key] { return cached }
        guard let root else { throw IssuerError.rootMissing }
        let leaf = try CertificateAuthority.issueLeafCertificate(
            for: key,
            signedBy: root,
            rootPrivateKeyPEM: root.privateKeyPEM
        )
        if cache.count >= maxCache { cache.removeAll(keepingCapacity: true) }
        let material = SSLCertificateMaterial(
            certificateChainPEM: leaf.certificateChainPEM,
            privateKeyPEM: leaf.privateKeyPEM
        )
        cache[key] = material
        return material
    }

    enum IssuerError: Error, LocalizedError {
        case rootMissing
        var errorDescription: String? { "Root CA is not available. Install the ShubhranshProxy certificate first." }
    }
}

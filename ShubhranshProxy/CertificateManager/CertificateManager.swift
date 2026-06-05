//
//  CertificateManager.swift
//  ShubhranshProxy — CertificateManager (Phase 2)
//  Created by Shubhransh Gupta
//

import Foundation

/// Generates and caches root/leaf certificates for HTTPS MITM.
actor CertificateManager {
    static let shared = CertificateManager()

    private var root: CertificateAuthority.RootMaterial?
    private var leafCache: [String: CertificateAuthority.LeafMaterial] = [:]
    private let maxLeafCache = 512

    func ensureRootCA() throws -> CertificateAuthority.RootMaterial {
        if let root { return root }
        if let loaded = try CertificateAuthority.loadPersistedRoot() {
            root = loaded
            return loaded
        }
        let generated = try CertificateAuthority.generateRootCA()
        try CertificateAuthority.persistRoot(generated)
        root = generated
        return generated
    }

    func resetRoot() {
        root = nil
        leafCache.removeAll()
    }

    func leafMaterial(for host: String) throws -> SSLCertificateMaterial {
        let normalized = host.lowercased()
        if let cached = leafCache[normalized] {
            return SSLCertificateMaterial(
                certificateChainPEM: cached.certificateChainPEM,
                privateKeyPEM: cached.privateKeyPEM
            )
        }
        let rootMaterial = try ensureRootCA()
        let leaf = try CertificateAuthority.issueLeafCertificate(
            for: normalized,
            signedBy: rootMaterial,
            rootPrivateKeyPEM: rootMaterial.privateKeyPEM
        )
        if leafCache.count >= maxLeafCache {
            leafCache.removeAll(keepingCapacity: true)
        }
        leafCache[normalized] = leaf
        return SSLCertificateMaterial(
            certificateChainPEM: leaf.certificateChainPEM,
            privateKeyPEM: leaf.privateKeyPEM
        )
    }

    func rootCertificateDER() throws -> Data {
        try ensureRootCA().certificateDER
    }

    /// Human-readable status for the SSL Proxying section of the app.
    static func sslProxyingStatus(
        rootInstalled: Bool,
        rootTrusted: Bool = true,
        sslEnabled: Bool,
        interceptAllHosts: Bool = false,
        includedHostCount: Int = 0
    ) -> String {
        if !rootInstalled {
            return "Setting up the ShubhranshProxy root CA… Plain HTTP works without it."
        }
        if !rootTrusted {
            return "Root CA is in Keychain — approve the macOS trust prompt to decrypt HTTPS."
        }
        if !sslEnabled {
            return "Root CA ready. Enable SSL Proxying to decrypt selected HTTPS hosts."
        }
        if interceptAllHosts {
            return "Decrypting all HTTPS hosts (except excluded). Apps like Slack may break — use selective decrypt instead."
        }
        if includedHostCount == 0 {
            return "Selective decrypt is ON — add hosts below to decrypt HTTPS. Other traffic passes through untouched."
        }
        return "Selective decrypt is ON — \(includedHostCount) host(s) configured for HTTPS decryption."
    }
}

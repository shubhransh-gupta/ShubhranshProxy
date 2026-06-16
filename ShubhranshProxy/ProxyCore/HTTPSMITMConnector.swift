//
//  HTTPSMITMConnector.swift
//  ShubhranshProxy — ProxyCore (Phase 2)
//  Created by Shubhransh Gupta
//

import Foundation
import NIOCore
import NIOPosix
import NIOSSL

enum HTTPSMITMConnector {
    static func makeServerSSLContext(material: SSLCertificateMaterial) throws -> NIOSSLContext {
        let certificates = try pemCertificates(from: material.certificateChainPEM)
        guard let first = certificates.first else {
            throw MITMError.missingCertificate
        }
        let chain: [NIOSSLCertificateSource] = certificates.map { .certificate($0) }
        let privateKey = try NIOSSLPrivateKey(bytes: Array(material.privateKeyPEM.utf8), format: .pem)
        var tlsConfig = TLSConfiguration.makeServerConfiguration(
            certificateChain: chain,
            privateKey: .privateKey(privateKey)
        )
        tlsConfig.certificateVerification = .none
        // Chrome negotiates HTTP/2 by default — force HTTP/1.1 so MITM can parse requests.
        tlsConfig.applicationProtocols = ["http/1.1"]
        _ = first
        return try NIOSSLContext(configuration: tlsConfig)
    }

    static func makeClientSSLContext() throws -> NIOSSLContext {
        var tlsConfig = TLSConfiguration.makeClientConfiguration()
        tlsConfig.certificateVerification = .none
        // Origin must speak HTTP/1.1 — we forward raw HTTP/1.1 bytes after TLS (not HTTP/2 frames).
        tlsConfig.applicationProtocols = ["http/1.1"]
        return try NIOSSLContext(configuration: tlsConfig)
    }

    static func pemCertificates(from chainPEM: String) throws -> [NIOSSLCertificate] {
        let marker = "-----END CERTIFICATE-----"
        let parts = chainPEM.components(separatedBy: marker)
        var certificates: [NIOSSLCertificate] = []
        for part in parts {
            let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let block = trimmed + "\n\(marker)\n"
            let cert = try NIOSSLCertificate(bytes: Array(block.utf8), format: .pem)
            certificates.append(cert)
        }
        return certificates
    }

    enum MITMError: Error, LocalizedError {
        case missingCertificate
        var errorDescription: String? { "Could not parse leaf certificate chain." }
    }
}

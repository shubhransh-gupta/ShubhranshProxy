//
//  CertificateAuthority.swift
//  ShubhranshProxy — Core (Phase 2)
//  Created by Shubhransh Gupta
//

import Crypto
import Foundation
import Security
import SwiftASN1
import X509

enum CertificateAuthority {
    static let rootCommonName = KeychainTrustHelper.rootLabel
    static let organizationName = "ShubhranshProxy"

    static var phase2Status: String {
        "Install the ShubhranshProxy root CA, enable SSL Proxying, and route HTTPS through the proxy to decrypt traffic."
    }

    struct RootMaterial: Sendable {
        var certificatePEM: String
        var privateKeyPEM: String
        var certificateDER: Data
    }

    struct LeafMaterial: Sendable {
        var certificateChainPEM: String
        var privateKeyPEM: String
    }

    static func certificatesDirectory() throws -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("ShubhranshProxy/certs", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func generateRootCA() throws -> RootMaterial {
        let privateKey = P256.Signing.PrivateKey()
        let publicKey = Certificate.PublicKey(privateKey.publicKey)

        let subject = try DistinguishedName {
            CommonName(rootCommonName)
            OrganizationName(organizationName)
        }

        let now = Date()
        let extensions = try Certificate.Extensions {
            Critical(
                BasicConstraints.isCertificateAuthority(maxPathLength: nil)
            )
            Critical(
                KeyUsage(digitalSignature: true, keyCertSign: true, cRLSign: true)
            )
        }

        let certificate = try Certificate(
            version: .v3,
            serialNumber: Certificate.SerialNumber(),
            publicKey: publicKey,
            notValidBefore: now,
            notValidAfter: now.addingTimeInterval(60 * 60 * 24 * 365 * 10),
            issuer: subject,
            subject: subject,
            extensions: extensions,
            issuerPrivateKey: .init(privateKey)
        )

        let certPEM = try certificate.serializeAsPEM().pemString
        let keyPEM = privateKey.pemRepresentation
        var serializer = DER.Serializer()
        try serializer.serialize(certificate)
        let der = Data(serializer.serializedBytes)

        return RootMaterial(certificatePEM: certPEM, privateKeyPEM: keyPEM, certificateDER: der)
    }

    static func issueLeafCertificate(
        for host: String,
        signedBy root: RootMaterial,
        rootPrivateKeyPEM: String
    ) throws -> LeafMaterial {
        let rootPrivateKey = try P256.Signing.PrivateKey(pemRepresentation: rootPrivateKeyPEM)
        let rootCertificate = try Certificate(derEncoded: Array(root.certificateDER))
        let rootSubject = rootCertificate.subject

        let leafPrivateKey = P256.Signing.PrivateKey()
        let leafPublicKey = Certificate.PublicKey(leafPrivateKey.publicKey)

        let leafSubject = try DistinguishedName {
            CommonName(host)
        }

        let now = Date()
        let extensions = try Certificate.Extensions {
            BasicConstraints.notCertificateAuthority
            SubjectAlternativeNames([.dnsName(host)])
            try ExtendedKeyUsage([.serverAuth, .clientAuth])
        }

        let leaf = try Certificate(
            version: .v3,
            serialNumber: Certificate.SerialNumber(),
            publicKey: leafPublicKey,
            notValidBefore: now,
            notValidAfter: now.addingTimeInterval(60 * 60 * 24 * 825),
            issuer: rootSubject,
            subject: leafSubject,
            extensions: extensions,
            issuerPrivateKey: .init(rootPrivateKey)
        )

        let leafPEM = try leaf.serializeAsPEM().pemString
        let chainPEM = leafPEM + "\n" + root.certificatePEM
        return LeafMaterial(certificateChainPEM: chainPEM, privateKeyPEM: leafPrivateKey.pemRepresentation)
    }

    static func secCertificate(from root: RootMaterial) -> SecCertificate? {
        SecCertificateCreateWithData(nil, root.certificateDER as CFData)
    }

    static func persistRoot(_ material: RootMaterial) throws {
        let dir = try certificatesDirectory()
        try material.certificatePEM.write(to: dir.appendingPathComponent("root.pem"), atomically: true, encoding: .utf8)
        try material.privateKeyPEM.write(to: dir.appendingPathComponent("root.key.pem"), atomically: true, encoding: .utf8)
        try material.certificateDER.write(to: dir.appendingPathComponent("root.der"))
    }

    static func loadPersistedRoot() throws -> RootMaterial? {
        let dir = try certificatesDirectory()
        let certURL = dir.appendingPathComponent("root.pem")
        let keyURL = dir.appendingPathComponent("root.key.pem")
        let derURL = dir.appendingPathComponent("root.der")
        guard FileManager.default.fileExists(atPath: certURL.path),
              FileManager.default.fileExists(atPath: keyURL.path),
              FileManager.default.fileExists(atPath: derURL.path) else { return nil }
        let certPEM = try String(contentsOf: certURL, encoding: .utf8)
        let keyPEM = try String(contentsOf: keyURL, encoding: .utf8)
        let der = try Data(contentsOf: derURL)
        return RootMaterial(certificatePEM: certPEM, privateKeyPEM: keyPEM, certificateDER: der)
    }

    static func rootPEMFileURL() throws -> URL {
        try certificatesDirectory().appendingPathComponent("root.pem")
    }
}

//
//  KeychainTrustHelper.swift
//  ShubhranshProxy — Core (Phase 2)
//  Created by Shubhransh Gupta
//

import Crypto
import Foundation
import Security

enum KeychainTrustHelper {
    static let rootLabel = "ShubhranshProxy Root CA"

    private static let fingerprintDefaultsKey = "ShubhranshProxy.rootCA.sha256"
    private static let trustedDefaultsKey = "ShubhranshProxy.rootCA.trusted"

    struct InstallResult: Sendable {
        var certificateInKeychain: Bool
        var userTrusted: Bool
        var usedSecurityCLI: Bool
    }

    static func isRootInstalled() -> Bool {
        findRootCertificate() != nil
    }

    /// Marks trust only when macOS actually trusts the cert — avoids enabling MITM with an untrusted CA.
    static func recognizeExistingTrustedRootIfPresent() {
        guard let cert = findRootCertificate() else { return }
        guard certificateIsTrustedForSSL(cert) else { return }
        UserDefaults.standard.set(true, forKey: trustedDefaultsKey)
        storeFingerprint(SecCertificateCopyData(cert) as Data)
    }

    static func rootCertificateMatchesAppRoot() -> Bool {
        guard let persisted = try? CertificateAuthority.loadPersistedRoot(),
              let keychainCert = findRootCertificate() else {
            return true
        }
        return SecCertificateCopyData(keychainCert) as Data == persisted.certificateDER
    }

    static func rootCertificateMismatchMessage() -> String? {
        guard findRootCertificate() != nil, !rootCertificateMatchesAppRoot() else { return nil }
        return """
        Keychain contains a different ShubhranshProxy root CA than this app is using. \
        Remove the old certificate, then click Reinstall & trust root CA.
        """
    }

    static func isRootUserTrusted() -> Bool {
        if let mismatch = rootCertificateMismatchMessage() {
            UserDefaults.standard.removeObject(forKey: trustedDefaultsKey)
            return false
        }
        guard let cert = findRootCertificate() else {
            UserDefaults.standard.removeObject(forKey: trustedDefaultsKey)
            return false
        }
        // Trust already confirmed (e.g. via Keychain Access) — do not re-run install flows that prompt for admin.
        if UserDefaults.standard.bool(forKey: trustedDefaultsKey), rootCertificateMatchesAppRoot() {
            return true
        }
        let trusted = certificateIsTrustedForSSL(cert)
        if trusted {
            UserDefaults.standard.set(true, forKey: trustedDefaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: trustedDefaultsKey)
        }
        return trusted
    }

    static func findRootCertificate() -> SecCertificate? {
        let candidates = allRootCertificateCandidates()
        guard !candidates.isEmpty else { return nil }

        // Prefer the copy macOS actually trusts (Keychain Access may trust a different ref than our search order).
        if let trusted = candidates.first(where: { certificateIsTrustedForSSL($0) }) {
            return trusted
        }

        let persisted = try? CertificateAuthority.loadPersistedRoot()
        if let persisted,
           let exact = candidates.first(where: { SecCertificateCopyData($0) as Data == persisted.certificateDER }) {
            return exact
        }

        return candidates.first { label(for: $0) == rootLabel } ?? candidates.first
    }

    private static func allRootCertificateCandidates() -> [SecCertificate] {
        deduplicated(
            searchCertificates(matchingSubject: rootLabel)
                + searchCertificates(matchingSubject: "ShubhranshProxy")
                + searchCertificates(matchingLabel: rootLabel)
        )
    }

    /// Installs and trusts the root CA using macOS `security add-trusted-cert` (Charles/Proxyman style).
    /// macOS may show a one-time password/Touch ID prompt — that is expected and replaces manual Keychain Access steps.
    static func installRootCertificate(from root: CertificateAuthority.RootMaterial) throws -> InstallResult {
        try CertificateAuthority.persistRoot(root)
        storeFingerprint(root.certificateDER)

        if let existing = findRootCertificate(), certificateIsTrustedForSSL(existing) {
            UserDefaults.standard.set(true, forKey: trustedDefaultsKey)
            return InstallResult(certificateInKeychain: true, userTrusted: true, usedSecurityCLI: false)
        }

        let pemURL = try CertificateAuthority.rootPEMFileURL()

        var usedCLI = false
        if let existing = findRootCertificate() {
            if certificateIsTrustedForSSL(existing) || UserDefaults.standard.bool(forKey: trustedDefaultsKey) {
                UserDefaults.standard.set(true, forKey: trustedDefaultsKey)
                usedCLI = false
            } else if (try? applyUserTrust(to: existing)) == true {
                usedCLI = false
            } else {
                do {
                    try runSecurityAddTrustedCert(pemURL: pemURL)
                    usedCLI = true
                } catch {
                    if certificateIsTrustedForSSL(existing) {
                        usedCLI = false
                    } else {
                        throw error
                    }
                }
            }
        } else {
            if let secCert = CertificateAuthority.secCertificate(from: root) {
                try? addCertificateToKeychain(secCert)
            }
            if let existing = findRootCertificate(), certificateIsTrustedForSSL(existing) {
                usedCLI = false
            } else if let existing = findRootCertificate(), (try? applyUserTrust(to: existing)) == true {
                usedCLI = false
            } else {
                do {
                    try runSecurityAddTrustedCert(pemURL: pemURL)
                    usedCLI = true
                } catch {
                    throw error
                }
            }
        }

        guard let installed = findRootCertificate() else {
            throw KeychainError.operationFailed(
                errSecItemNotFound,
                "Certificate install did not complete. Try exporting the root CA and double-clicking it in Finder."
            )
        }

        let trusted = certificateIsTrustedForSSL(installed)
        if trusted {
            UserDefaults.standard.set(true, forKey: trustedDefaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: trustedDefaultsKey)
        }
        return InstallResult(
            certificateInKeychain: true,
            userTrusted: trusted,
            usedSecurityCLI: usedCLI
        )
    }

    static func installRootCertificate(_ certificate: SecCertificate) throws -> InstallResult {
        try addCertificateToKeychain(certificate)
        let trusted = try applyUserTrust(to: certificate)
        return InstallResult(certificateInKeychain: true, userTrusted: trusted, usedSecurityCLI: false)
    }

    static func removeRootCertificate() throws {
        if let cert = findRootCertificate() {
            _ = SecTrustSettingsRemoveTrustSettings(cert, SecTrustSettingsDomain.user)
            let query: [String: Any] = [
                kSecClass as String: kSecClassCertificate,
                kSecValueRef as String: cert,
            ]
            _ = SecItemDelete(query as CFDictionary)
        }
        UserDefaults.standard.removeObject(forKey: fingerprintDefaultsKey)
        UserDefaults.standard.removeObject(forKey: trustedDefaultsKey)
    }

    static func exportRootCertificateDER(from root: CertificateAuthority.RootMaterial) -> Data {
        root.certificateDER
    }

    static func exportRootCertificatePEM(from root: CertificateAuthority.RootMaterial) -> String {
        root.certificatePEM
    }

    static func exportRootCertificateData() throws -> Data {
        if let cert = findRootCertificate() {
            return SecCertificateCopyData(cert) as Data
        }
        if let root = try CertificateAuthority.loadPersistedRoot() {
            return root.certificateDER
        }
        throw KeychainError.notInstalled
    }

    // MARK: - Private

    private static func loginKeychainURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Keychains/login.keychain-db")
    }

    private static func runSecurityAddTrustedCert(pemURL: URL) throws {
        let security = try SystemCommandRunner.executableURL(named: "security")
        let arguments = [
            "add-trusted-cert",
            "-r", "trustRoot",
            "-k", loginKeychainURL().path,
            pemURL.path,
        ]

        // Login keychain trust usually does not need admin — try that first to avoid extra password prompts.
        let process = Process()
        process.executableURL = security
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()

        let message = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if process.terminationStatus == 0 {
            return
        }

        let lowered = message.lowercased()
        if lowered.contains("already") || lowered.contains("duplicate") {
            if let cert = findRootCertificate(), certificateIsTrustedForSSL(cert) {
                return
            }
            throw KeychainError.operationFailed(
                process.terminationStatus,
                untrustedInKeychainMessage
            )
        }

        // Never escalate to admin here — cert is in login keychain; trust via Keychain Access instead.
        throw KeychainError.operationFailed(
            process.terminationStatus,
            message.isEmpty ? untrustedInKeychainMessage : message
        )
    }

    private static func addCertificateToKeychain(_ certificate: SecCertificate) throws {
        let add: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecValueRef as String: certificate,
            kSecAttrLabel as String: rootLabel,
        ]
        let status = SecItemAdd(add as CFDictionary, nil)
        if status != errSecSuccess, status != errSecDuplicateItem {
            throw KeychainError.operationFailed(status, "Could not add root certificate to Keychain.")
        }
    }

    @discardableResult
    private static func applyUserTrust(to certificate: SecCertificate) throws -> Bool {
        if certificateIsTrustedForSSL(certificate) {
            UserDefaults.standard.set(true, forKey: trustedDefaultsKey)
            return true
        }

        let policy = SecPolicyCreateBasicX509()
        let settings: [String: Any] = [
            kSecTrustSettingsPolicy as String: policy,
            kSecTrustSettingsResult as String: SecTrustSettingsResult.trustRoot,
        ]
        let status = SecTrustSettingsSetTrustSettings(
            certificate,
            SecTrustSettingsDomain.user,
            settings as CFDictionary
        )
        if status == errSecSuccess {
            UserDefaults.standard.set(true, forKey: trustedDefaultsKey)
            return true
        }

        if certificateIsTrustedForSSL(certificate) {
            UserDefaults.standard.set(true, forKey: trustedDefaultsKey)
            return true
        }
        if status == -25293 || status == -25308 {
            return certificateIsTrustedForSSL(certificate)
        }
        throw KeychainError.operationFailed(status, untrustedInKeychainMessage)
    }

    private static let untrustedInKeychainMessage =
        """
        Certificate is in Keychain but not trusted. Click "Reinstall & trust root CA" and approve the macOS password prompt, \
        or open Keychain Access → login → Certificates → "ShubhranshProxy Root CA" → Trust → "Always Trust" for SSL.
        """

    /// macOS can mark a cert trusted via Keychain Access without populating SecTrustSettings entries.
    /// Match Charles/Proxyman behavior: trust if the cert is in the trust DB or passes SSL verification.
    private static func certificateIsTrustedForSSL(_ certificate: SecCertificate) -> Bool {
        if isCertificateListedInTrustDatabase(certificate) {
            return true
        }
        if trustSettingsGrantRootTrust(for: certificate, domain: .user)
            || trustSettingsGrantRootTrust(for: certificate, domain: .admin) {
            return true
        }
        if macOSVerifiesCertificateForSSL(certificate) {
            return true
        }
        return false
    }

    private static func isCertificateListedInTrustDatabase(_ certificate: SecCertificate) -> Bool {
        let der = SecCertificateCopyData(certificate) as Data
        for domain in [SecTrustSettingsDomain.user, SecTrustSettingsDomain.admin] {
            var listed: CFArray?
            guard SecTrustSettingsCopyCertificates(domain, &listed) == errSecSuccess,
                  let certificates = listed as? [SecCertificate] else { continue }
            if certificates.contains(where: { SecCertificateCopyData($0) as Data == der }) {
                return true
            }
        }
        return false
    }

    private static func macOSVerifiesCertificateForSSL(_ certificate: SecCertificate) -> Bool {
        for policy in [SecPolicyCreateSSL(true, nil), SecPolicyCreateBasicX509()] {
            var trust: SecTrust?
            guard SecTrustCreateWithCertificates([certificate] as CFArray, policy, &trust) == errSecSuccess,
                  let trust else { continue }

            SecTrustSetAnchorCertificates(trust, [certificate] as CFArray)
            SecTrustSetAnchorCertificatesOnly(trust, true)

            var error: CFError?
            if SecTrustEvaluateWithError(trust, &error) {
                return true
            }
        }
        return false
    }

    private static func trustSettingsGrantRootTrust(
        for certificate: SecCertificate,
        domain: SecTrustSettingsDomain
    ) -> Bool {
        var trustSettings: CFArray?
        let status = SecTrustSettingsCopyTrustSettings(certificate, domain, &trustSettings)
        guard status == errSecSuccess,
              let settings = trustSettings as? [[String: Any]],
              !settings.isEmpty else {
            return false
        }

        return settings.contains { entry in
            if let resultNumber = entry[kSecTrustSettingsResult as String] as? NSNumber {
                let result = resultNumber.intValue
                return result == SecTrustSettingsResult.trustRoot.rawValue
                    || result == SecTrustSettingsResult.trustAsRoot.rawValue
                    || (result != 3 && entry[kSecTrustSettingsPolicyString as String] != nil)
            }
            guard let result = entry[kSecTrustSettingsResult as String] as? Int else {
                return entry[kSecTrustSettingsPolicy as String] != nil
                    || entry[kSecTrustSettingsPolicyString as String] != nil
            }
            return result == SecTrustSettingsResult.trustRoot.rawValue
                || result == SecTrustSettingsResult.trustAsRoot.rawValue
                || (result != 3 && entry[kSecTrustSettingsPolicyString as String] != nil)
        }
    }

    private static func deduplicated(_ certificates: [SecCertificate]) -> [SecCertificate] {
        var seen = Set<Data>()
        var unique: [SecCertificate] = []
        for cert in certificates {
            let der = SecCertificateCopyData(cert) as Data
            guard seen.insert(der).inserted else { continue }
            unique.append(cert)
        }
        return unique
    }

    private static func searchCertificates(matchingLabel label: String) -> [SecCertificate] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecAttrLabel as String: label,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnRef as String: true,
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let result else { return [] }
        return certificates(from: result)
    }

    private static func searchCertificates(matchingSubject subject: String) -> [SecCertificate] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecMatchSubjectContains as String: subject,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnRef as String: true,
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let result else { return [] }

        return certificates(from: result)
    }

    private static func certificates(from result: CFTypeRef) -> [SecCertificate] {
        let typeID = CFGetTypeID(result)
        if typeID == SecCertificateGetTypeID() {
            return [unsafeBitCast(result, to: SecCertificate.self)]
        }
        if typeID == CFArrayGetTypeID() {
            let array = unsafeBitCast(result, to: CFArray.self)
            let count = CFArrayGetCount(array)
            var certs: [SecCertificate] = []
            certs.reserveCapacity(count)
            for index in 0..<count {
                guard let value = CFArrayGetValueAtIndex(array, index) else { continue }
                let item = Unmanaged<AnyObject>.fromOpaque(value).takeUnretainedValue()
                if CFGetTypeID(item) == SecCertificateGetTypeID() {
                    certs.append(unsafeBitCast(item, to: SecCertificate.self))
                }
            }
            return certs
        }
        return []
    }

    private static func label(for certificate: SecCertificate) -> String? {
        var commonName: CFString?
        guard SecCertificateCopyCommonName(certificate, &commonName) == errSecSuccess,
              let cn = commonName as String? else { return nil }
        return cn
    }

    private static func storeFingerprint(_ der: Data) {
        let digest = SHA256.hash(data: der)
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(hex, forKey: fingerprintDefaultsKey)
    }

    enum KeychainError: Error, LocalizedError {
        case notInstalled
        case operationFailed(OSStatus, String)
        var errorDescription: String? {
            switch self {
            case .notInstalled: return "Root certificate is not installed."
            case .operationFailed(_, let message): return message
            }
        }
    }
}

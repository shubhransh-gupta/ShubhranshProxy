//
//  TLSManager.swift
//  ShubhranshProxy — Core (Phase 2)
//  Created by Shubhransh Gupta
//

import Foundation

@MainActor
@Observable
final class TLSManager {
    private static let sslSettingsKey = "ShubhranshProxy.sslSettings"
    private static let sslProxyingEnabledKey = "ShubhranshProxy.sslProxyingEnabled"
    private static let selectiveDecryptMigrationKey = "ShubhranshProxy.ssl.selectiveDecryptMigration.v1"
    private static let remoteDeviceDecryptMigrationKey = "ShubhranshProxy.ssl.remoteDeviceDecryptMigration.v1"

    var sslProxyingEnabled = false
    var rootCertificateInstalled = false
    var rootCertificateTrusted = false
    var sslSettings = SSLProxySettings()
    var lastTrustError: String?
    var isPreparingCertificate = false

    var statusMessage: String {
        CertificateManager.sslProxyingStatus(
            rootInstalled: rootCertificateInstalled,
            rootTrusted: rootCertificateTrusted,
            sslEnabled: sslProxyingEnabled && sslSettings.isEnabled,
            interceptAllHosts: sslSettings.interceptAllHosts,
            includedHostCount: sslSettings.includedHosts.count
        )
    }

    init() {
        loadPersistedSettings()
        refreshInstallationState()
    }

    func loadPersistedSettings() {
        if let data = UserDefaults.standard.data(forKey: Self.sslSettingsKey),
           let loaded = try? JSONDecoder().decode(SSLProxySettings.self, from: data) {
            sslSettings = loaded
        }
        if UserDefaults.standard.object(forKey: Self.sslProxyingEnabledKey) != nil {
            sslProxyingEnabled = UserDefaults.standard.bool(forKey: Self.sslProxyingEnabledKey)
        }
        applySelectiveDecryptMigrationIfNeeded()
        applyRemoteDeviceDecryptMigrationIfNeeded()
        applyPreferredDecryptHostsIfNeeded()
    }

    private func applyPreferredDecryptHostsIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: PreferredDecryptHosts.migrationKey) else { return }
        if PreferredDecryptHosts.merge(into: &sslSettings) {
            sslSettings.interceptAllHosts = false
            sslProxyingEnabled = true
            sslSettings.isEnabled = true
        }
        UserDefaults.standard.set(true, forKey: PreferredDecryptHosts.migrationKey)
        persistSettings()
    }

    private func applyRemoteDeviceDecryptMigrationIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: Self.remoteDeviceDecryptMigrationKey) else { return }
        sslSettings.interceptRemoteDevices = true
        UserDefaults.standard.set(true, forKey: Self.remoteDeviceDecryptMigrationKey)
        persistSettings()
    }

    private func applySelectiveDecryptMigrationIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: Self.selectiveDecryptMigrationKey) else { return }
        sslSettings.interceptAllHosts = false
        UserDefaults.standard.set(true, forKey: Self.selectiveDecryptMigrationKey)
        persistSettings()
    }

    func persistSettings() {
        if let data = try? JSONEncoder().encode(sslSettings) {
            UserDefaults.standard.set(data, forKey: Self.sslSettingsKey)
        }
        UserDefaults.standard.set(sslProxyingEnabled, forKey: Self.sslProxyingEnabledKey)
    }

    func refreshInstallationState() {
        KeychainTrustHelper.recognizeExistingTrustedRootIfPresent()
        rootCertificateInstalled = KeychainTrustHelper.isRootInstalled()
        rootCertificateTrusted = KeychainTrustHelper.isRootUserTrusted()
        if let mismatch = KeychainTrustHelper.rootCertificateMismatchMessage() {
            lastTrustError = mismatch
            rootCertificateTrusted = false
        } else if rootCertificateTrusted {
            lastTrustError = nil
        }
    }

    var effectiveSSLSettings: SSLProxySettings {
        var settings = sslSettings
        settings.isEnabled = sslProxyingEnabled && rootCertificateInstalled
        return settings
    }

    /// Generates (if needed), installs in Keychain, trusts for SSL proxying, and enables SSL automatically.
    @discardableResult
    func ensureRootCertificateReady() async throws -> KeychainTrustHelper.InstallResult {
        refreshInstallationState()
        if rootCertificateInstalled, rootCertificateTrusted {
            lastTrustError = nil
            return KeychainTrustHelper.InstallResult(
                certificateInKeychain: true,
                userTrusted: true,
                usedSecurityCLI: false
            )
        }

        isPreparingCertificate = true
        defer {
            isPreparingCertificate = false
            refreshInstallationState()
        }
        lastTrustError = nil

        let root = try await CertificateManager.shared.ensureRootCA()
        let result = try KeychainTrustHelper.installRootCertificate(from: root)

        rootCertificateInstalled = result.certificateInKeychain
        refreshInstallationState()
        rootCertificateTrusted = KeychainTrustHelper.isRootUserTrusted()

        if result.certificateInKeychain {
            sslSettings.isEnabled = true
            sslProxyingEnabled = true
        }

        if rootCertificateTrusted {
            lastTrustError = nil
        } else if result.certificateInKeychain {
            lastTrustError =
                "Root CA is in Keychain but macOS has not confirmed SSL trust yet. Open Keychain Access → login → ShubhranshProxy Root CA → Trust → Always Trust, then click Refresh trust status in SSL Proxy."
        }

        return result
    }

    func installRootCertificate() async throws {
        _ = try await ensureRootCertificateReady()
    }

    func removeRootCertificate() async throws {
        try KeychainTrustHelper.removeRootCertificate()
        await CertificateManager.shared.resetRoot()
        rootCertificateInstalled = false
        rootCertificateTrusted = false
        sslProxyingEnabled = false
        sslSettings.isEnabled = false
    }

    func exportRootCertificateURL(format: RootCertificateExportFormat) async throws -> URL {
        let root = try await CertificateManager.shared.ensureRootCA()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShubhranshProxy-Root-CA.\(format.fileExtension)")
        switch format {
        case .cer:
            try root.certificateDER.write(to: url)
        case .pem:
            try root.certificatePEM.write(to: url, atomically: true, encoding: .utf8)
        }
        return url
    }

    enum TLSManagerError: Error, LocalizedError {
        case invalidCertificate
        var errorDescription: String? { "Could not create a valid root certificate." }
    }
}

enum RootCertificateExportFormat: String, CaseIterable, Identifiable {
    case cer
    case pem

    var id: String { rawValue }
    var label: String {
        switch self {
        case .cer: "Certificate (.cer)"
        case .pem: "PEM (.pem)"
        }
    }
    var fileExtension: String { rawValue }
}

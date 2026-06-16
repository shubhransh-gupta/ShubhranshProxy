//
//  LegacyBundledHostCleanup.swift
//  ShubhranshProxy — removes one-time bundled defaults from older builds.
//

import Foundation

enum LegacyBundledHostCleanup {
    private static let migrationKey = "ShubhranshProxy.removedBundledHosts.v2"

    /// Hosts that were previously auto-pinned or auto-added to SSL decrypt — never bundled again.
    static let legacyHosts: Set<String> = [
        "api-gateway.juno.lenskart.com",
        "api-gateway.juno.preprod.lenskart.com",
        "apigateway.zuno.lenscar.com",
        "apigateway.zuno.preprod.lenscar.com",
    ]

    @MainActor
    static func applyIfNeeded(favorites: FavoritesStore, tls: TLSManager) {
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }

        for host in legacyHosts {
            favorites.unpin(host)
        }

        var settings = tls.sslSettings
        let before = settings.includedHosts.count
        settings.includedHosts.removeAll { legacyHosts.contains($0.lowercased()) }
        if settings.includedHosts.count != before {
            tls.sslSettings = settings
            tls.persistSettings()
        }

        UserDefaults.standard.set(true, forKey: migrationKey)
    }
}

//
//  FavoritesStore.swift
//  ShubhranshProxy — Features (Phase 3)
//  Created by Shubhransh Gupta
//

import Foundation
import Observation

@MainActor
@Observable
final class FavoritesStore {
    private static let hostsKey = "ShubhranshProxy.favoriteHosts"
    private static let endpointsKey = "ShubhranshProxy.favoriteEndpoints"

    private var isLoading = false

    var favoriteHosts: Set<String> = [] {
        didSet {
            guard !isLoading else { return }
            persistHosts()
        }
    }

    var favoriteEndpoints: Set<String> = [] {
        didSet {
            guard !isLoading else { return }
            persistEndpoints()
        }
    }

    init() {
        load()
    }

    static func normalizedHost(from value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return "" }
        if trimmed.contains("://"), let host = URL(string: trimmed)?.host {
            return host.lowercased()
        }
        if trimmed.contains("/") {
            return trimmed.split(separator: "/").first.map(String.init)?.lowercased() ?? trimmed
        }
        return trimmed
    }

    func pin(_ host: String) {
        let key = Self.normalizedHost(from: host)
        guard !key.isEmpty else { return }
        favoriteHosts.insert(key)
    }

    func unpin(_ host: String) {
        favoriteHosts.remove(Self.normalizedHost(from: host))
    }

    func toggle(_ host: String) {
        let key = Self.normalizedHost(from: host)
        guard !key.isEmpty else { return }
        if favoriteHosts.contains(key) {
            favoriteHosts.remove(key)
        } else {
            favoriteHosts.insert(key)
        }
    }

    func isFavorite(_ host: String) -> Bool {
        favoriteHosts.contains(Self.normalizedHost(from: host))
    }

    func pinEndpoint(_ url: String) {
        let key = SessionDisplayRules.normalizedURLKey(url)
        guard !key.isEmpty else { return }
        favoriteEndpoints.insert(key)
    }

    func unpinEndpoint(_ url: String) {
        favoriteEndpoints.remove(SessionDisplayRules.normalizedURLKey(url))
    }

    func toggleEndpoint(_ url: String) {
        let key = SessionDisplayRules.normalizedURLKey(url)
        if favoriteEndpoints.contains(key) {
            favoriteEndpoints.remove(key)
        } else {
            favoriteEndpoints.insert(key)
        }
    }

    func isFavoriteEndpoint(_ url: String) -> Bool {
        favoriteEndpoints.contains(SessionDisplayRules.normalizedURLKey(url))
    }

    var sortedFavorites: [String] {
        favoriteHosts.sorted()
    }

    private func normalizedHost(_ value: String) -> String {
        Self.normalizedHost(from: value)
    }

    private func persistHosts() {
        UserDefaults.standard.set(Array(favoriteHosts).sorted(), forKey: Self.hostsKey)
    }

    private func persistEndpoints() {
        UserDefaults.standard.set(Array(favoriteEndpoints).sorted(), forKey: Self.endpointsKey)
    }

    private func load() {
        isLoading = true
        defer { isLoading = false }
        if let savedHosts = UserDefaults.standard.stringArray(forKey: Self.hostsKey) {
            favoriteHosts = Set(savedHosts.map { $0.lowercased() })
        }
        if let savedEndpoints = UserDefaults.standard.stringArray(forKey: Self.endpointsKey) {
            favoriteEndpoints = Set(savedEndpoints)
        }
    }
}

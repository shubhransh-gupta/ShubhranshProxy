//
//  DomainsSidebarView.swift
//  ShubhranshProxy — Proxyman-style: Pinned domains + expandable All/Domains
//
//  Created by Shubhransh Gupta
//

import SwiftUI

struct DomainsSidebarView: View {
    @Environment(AppState.self) private var appState
    @State private var sidebarSearch = ""
    @State private var expandedFavorites: Set<String> = SidebarDefaults.loadExpansionKeys(SidebarDefaults.expandedFavoritesKey)
    @State private var expandedDevices: Set<String> = SidebarDefaults.loadExpansionKeys(SidebarDefaults.expandedDevicesKey)
    @State private var expandedDomains: Set<String> = SidebarDefaults.loadExpansionKeys(SidebarDefaults.expandedDomainsKey)
    @State private var isAllSectionExpanded = UserDefaults.standard.object(forKey: SidebarDefaults.allSectionExpandedKey) as? Bool ?? true

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            TextField("Filter", text: $sidebarSearch)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            Divider()
            sidebarList
        }
        .background(.background)
        .safeAreaInset(edge: .bottom) {
            sidebarFooter
        }
        .onAppear {
            seedExpandedPinnedIfNeeded()
            autoExpandPinnedGroupsWithTraffic()
            seedExpandedMacDeviceIfNeeded()
        }
        .onChange(of: appState.sessions.sessions.count) { _, _ in
            autoExpandPinnedGroupsWithTraffic()
        }
        .onChange(of: appState.remoteDeviceIPs) { _, _ in
            autoExpandConnectedDevicesIfNeeded()
        }
        .onChange(of: appState.sidebarPinnedGroups.map(\.endpoints.count)) { _, _ in
            autoExpandPinnedGroupsWithTraffic()
        }
    }

    private var header: some View {
        HStack {
            Text("Domains")
                .font(.headline)
            Spacer()
            if hasActiveFilter {
                Button("Clear") { appState.clearTrafficFilters() }
                    .font(.caption)
                    .buttonStyle(.link)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var sidebarList: some View {
        List {
            if !filteredPinnedGroups.isEmpty {
                Section {
                    ForEach(filteredPinnedGroups) { group in
                        let expansionKey = SidebarExpansionKey.host(group.host)
                        sidebarExpandableRow(
                            isExpanded: binding(
                                for: expansionKey,
                                in: $expandedFavorites,
                                persistKey: SidebarDefaults.expandedFavoritesKey
                            ),
                            isSelected: isDomainSelected(group, deviceKey: nil),
                            onSelect: { selectDomainFromSidebar(group, pinned: true) }
                        ) {
                            pinnedGroupLabelContent(group)
                        } content: {
                            if group.endpoints.isEmpty {
                                Text("No requests yet — pinned domain will appear here when traffic arrives.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.vertical, 4)
                                    .padding(.leading, 20)
                            } else {
                                ForEach(group.endpoints) { endpoint in
                                    endpointRow(endpoint)
                                        .padding(.leading, 20)
                                }
                            }
                        }
                        .id(expansionKey)
                        .contextMenu {
                            domainContextMenu(for: group)
                        }
                    }
                } header: {
                    Label("Pinned", systemImage: "star.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(nil)
                }
            }

            Section {
                DisclosureGroup(
                    isExpanded: Binding(
                        get: { isAllSectionExpanded },
                        set: { value in
                            isAllSectionExpanded = value
                            UserDefaults.standard.set(value, forKey: SidebarDefaults.allSectionExpandedKey)
                        }
                    ),
                    content: {
                        if filteredDeviceGroups.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("No devices connected yet.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if appState.isRunning, appState.acceptsRemoteDeviceConnections {
                                    Text(appState.deviceProxySetupHint)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("Start capture to see devices here.")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        } else {
                            ForEach(filteredDeviceGroups) { device in
                                let deviceExpansionKey = device.id
                                sidebarExpandableRow(
                                    isExpanded: binding(
                                        for: deviceExpansionKey,
                                        in: $expandedDevices,
                                        persistKey: SidebarDefaults.expandedDevicesKey
                                    ),
                                    isSelected: isDeviceSelected(device),
                                    onSelect: { selectDeviceFromSidebar(device) }
                                ) {
                                    deviceGroupLabelContent(device)
                                } content: {
                                    if device.domainGroups.isEmpty {
                                        if appState.remoteDeviceIPs.contains(where: { device.id.hasSuffix($0) }) {
                                            Text("Connected — waiting for requests…")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .padding(.vertical, 4)
                                                .padding(.leading, 20)
                                        } else {
                                            Text("No traffic from this device yet.")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .padding(.vertical, 4)
                                                .padding(.leading, 20)
                                        }
                                    } else {
                                        ForEach(filterDomains(device.domainGroups), id: \.baseURL) { group in
                                            let domainKey = SidebarExpansionKey.deviceDomain(deviceID: device.id, host: group.host)
                                            sidebarExpandableRow(
                                                isExpanded: binding(
                                                    for: domainKey,
                                                    in: $expandedDomains,
                                                    persistKey: SidebarDefaults.expandedDomainsKey
                                                ),
                                                isSelected: isDomainSelected(group, deviceKey: device.id),
                                                onSelect: { selectDomainFromSidebar(group, pinned: false, deviceKey: device.id) }
                                            ) {
                                                deviceDomainLabelContent(group, deviceKey: device.id)
                                            } content: {
                                                ForEach(group.endpoints) { endpoint in
                                                    endpointRow(endpoint, deviceKey: device.id)
                                                        .padding(.leading, 20)
                                                }
                                            }
                                            .id(domainKey)
                                            .padding(.leading, 12)
                                            .contextMenu {
                                                domainContextMenu(for: group, deviceKey: device.id)
                                            }
                                        }
                                    }
                                }
                                .id(device.id)
                            }
                        }
                    },
                    label: {
                        Label("All", systemImage: "tray.full")
                            .font(.caption.weight(.medium))
                    }
                )
            } header: {
                Text("Devices")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textCase(nil)
            }
        }
        .listStyle(.sidebar)
    }

    private func deviceSubtitle(_ device: TrafficDeviceGroup) -> String {
        if device.sessionCount == 0,
           appState.remoteDeviceIPs.contains(where: { device.id.hasSuffix($0) }) {
            return "Connected · waiting for requests"
        }
        return "\(device.domainGroups.count) hosts · \(device.sessionCount) requests"
    }

    private func sidebarExpandableRow<Label: View, Content: View>(
        isExpanded: Binding<Bool>,
        isSelected: Bool,
        onSelect: @escaping () -> Void,
        @ViewBuilder label: () -> Label,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isExpanded.wrappedValue.toggle()
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 16, height: 16)
                        .rotationEffect(.degrees(isExpanded.wrappedValue ? 90 : 0))
                }
                .buttonStyle(.plain)
                .help(isExpanded.wrappedValue ? "Collapse" : "Expand")

                Button(action: onSelect) {
                    label()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 2)

            if isExpanded.wrappedValue {
                content()
            }
        }
        .listRowBackground(isSelected ? Color.accentColor.opacity(0.12) : nil)
    }

    private func pinnedGroupLabelContent(_ group: APIBaseGroup) -> some View {
        HStack {
            Image(systemName: "star.fill")
                .font(.caption2)
                .foregroundStyle(.yellow)
            Text(group.host)
                .font(.callout)
                .lineLimit(1)
            Spacer()
            Text(group.endpoints.isEmpty ? "pinned" : "\(group.endpoints.count)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(isDomainSelected(group, deviceKey: nil) ? Color.accentColor : Color.primary)
        .help("Filter requests for \(group.host)")
    }

    private func deviceGroupLabelContent(_ device: TrafficDeviceGroup) -> some View {
        HStack {
            Image(systemName: device.systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(device.displayName)
                    .font(.callout)
                    .lineLimit(1)
                Text(deviceSubtitle(device))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isDeviceSelected(device) {
                Image(systemName: "line.3.horizontal.decrease.circle.fill")
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
            }
        }
        .foregroundStyle(isDeviceSelected(device) ? Color.accentColor : Color.primary)
        .help("Filter traffic from \(device.displayName)")
    }

    private func deviceDomainLabelContent(_ group: APIBaseGroup, deviceKey: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(group.host)
                    .font(.callout)
                    .lineLimit(1)
                Text("\(group.endpoints.count) APIs · \(group.totalRequests) requests")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isDomainSelected(group, deviceKey: deviceKey) {
                Image(systemName: "line.3.horizontal.decrease.circle.fill")
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
            }
        }
        .foregroundStyle(isDomainSelected(group, deviceKey: deviceKey) ? Color.accentColor : Color.primary)
        .help("Filter requests for \(group.host)")
    }

    @ViewBuilder
    private func domainContextMenu(for group: APIBaseGroup, deviceKey: String? = nil) -> some View {
        Button("Show all requests for domain") {
            selectDomainFromSidebar(group, pinned: deviceKey == nil, deviceKey: deviceKey)
        }
        if !appState.tls.sslSettings.interceptAllHosts {
            if appState.isDecryptEnabled(for: group.host) {
                Button("Stop decrypting HTTPS for this domain") {
                    appState.removeDecryptHost(group.host)
                }
            } else {
                Button("Decrypt HTTPS for this domain") {
                    appState.addDecryptHost(group.host)
                }
            }
        }
        Button(appState.features.favorites.isFavorite(group.host) ? "Unpin domain" : "Pin domain") {
            appState.features.favorites.toggle(group.host)
            if appState.features.favorites.isFavorite(group.host) {
                expandedFavorites.insert(SidebarExpansionKey.host(group.host))
                SidebarDefaults.saveExpansionKeys(expandedFavorites, key: SidebarDefaults.expandedFavoritesKey)
            }
        }
    }

    private func endpointRow(_ endpoint: APIEndpointSummary, deviceKey: String? = nil) -> some View {
        Button {
            if let deviceKey {
                appState.selectedDeviceFilter = deviceKey
            }
            appState.selectEndpoint(endpoint)
        } label: {
            HStack(spacing: 6) {
                Text(endpoint.method)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(methodColor(endpoint.method))
                    .frame(width: 36, alignment: .leading)
                Text(endpoint.path)
                    .font(.caption)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 2)
                Text("\(endpoint.count)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(appState.selectedEndpointKey == endpoint.endpointKey ? Color.accentColor.opacity(0.15) : nil)
        .contextMenu {
            endpointContextMenu(endpoint)
        }
    }

    @ViewBuilder
    private func endpointContextMenu(_ endpoint: APIEndpointSummary) -> some View {
        Button("Filter requests") { appState.selectEndpoint(endpoint) }
        Button(appState.features.favorites.isFavorite(endpoint.host) ? "Unpin domain" : "Pin domain") {
            appState.features.favorites.toggle(endpoint.host)
        }
        Button(appState.features.favorites.isFavoriteEndpoint(endpoint.fullURL) ? "Unpin endpoint" : "Pin endpoint") {
            appState.features.favorites.toggleEndpoint(endpoint.fullURL)
        }
        Button("Map Local…") {
            appState.presentMappingTools(
                prefill: MappingToolsPrefill(mode: .mapLocal, matchURL: endpoint.fullURL)
            )
        }
        Button("Map Remote…") {
            appState.presentMappingTools(prefill: MappingToolsPrefill(mode: .mapRemote, matchURL: endpoint.fullURL))
        }
        Button("Copy URL") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(endpoint.fullURL, forType: .string)
        }
    }

    private var sidebarFooter: some View {
        VStack(alignment: .leading, spacing: 4) {
            Divider()
            HStack(spacing: 6) {
                Circle()
                    .fill(appState.isRunning ? Color.green : Color.secondary.opacity(0.5))
                    .frame(width: 8, height: 8)
                Text(appState.isRunning ? "Capturing" : "Stopped")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    Task { await appState.toggleProxy() }
                } label: {
                    Label(appState.isRunning ? "Stop" : "Start", systemImage: appState.isRunning ? "stop.fill" : "play.fill")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                Text("\(appState.sessions.sessions.filter(SessionDisplayRules.shouldCapture).count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if let filter = activeFilterLabel {
                Text(filter)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var filteredDeviceGroups: [TrafficDeviceGroup] {
        guard !sidebarSearch.isEmpty else { return appState.trafficDeviceGroups }
        return appState.trafficDeviceGroups.compactMap { device in
            let domains = filterDomains(device.domainGroups)
            let nameMatches = device.displayName.localizedCaseInsensitiveContains(sidebarSearch)
            guard nameMatches || !domains.isEmpty else { return nil }
            return TrafficDeviceGroup(
                id: device.id,
                displayName: device.displayName,
                systemImage: device.systemImage,
                sessionCount: domains.isEmpty ? device.sessionCount : domains.reduce(0) { $0 + $1.totalRequests },
                domainGroups: domains
            )
        }
    }

    private func filterDomains(_ groups: [APIBaseGroup]) -> [APIBaseGroup] {
        filterGroups(groups)
    }

    private var filteredPinnedGroups: [APIBaseGroup] {
        filterGroups(appState.sidebarPinnedGroups)
    }

    private func filterGroups(_ groups: [APIBaseGroup]) -> [APIBaseGroup] {
        guard !sidebarSearch.isEmpty else { return groups }
        return groups.compactMap { group in
            let endpoints = group.endpoints.filter {
                group.host.localizedCaseInsensitiveContains(sidebarSearch)
                    || group.baseURL.localizedCaseInsensitiveContains(sidebarSearch)
                    || $0.path.localizedCaseInsensitiveContains(sidebarSearch)
                    || $0.method.localizedCaseInsensitiveContains(sidebarSearch)
            }
            let hostMatches = group.host.localizedCaseInsensitiveContains(sidebarSearch)
                || group.baseURL.localizedCaseInsensitiveContains(sidebarSearch)
            guard hostMatches || !endpoints.isEmpty else { return nil }
            return APIBaseGroup(
                baseURL: group.baseURL,
                host: group.host,
                totalRequests: endpoints.isEmpty ? group.totalRequests : endpoints.reduce(0) { $0 + $1.count },
                endpoints: endpoints
            )
        }
    }

    private func binding(for key: String, in set: Binding<Set<String>>, persistKey: String) -> Binding<Bool> {
        Binding(
            get: { set.wrappedValue.contains(key) },
            set: { expanded in
                if expanded {
                    set.wrappedValue.insert(key)
                } else {
                    set.wrappedValue.remove(key)
                }
                DispatchQueue.main.async {
                    SidebarDefaults.saveExpansionKeys(set.wrappedValue, key: persistKey)
                }
            }
        )
    }

    private func seedExpandedMacDeviceIfNeeded() {
        guard expandedDevices.isEmpty else { return }
        expandedDevices.insert(TrafficDeviceCatalog.macDeviceKey)
        SidebarDefaults.saveExpansionKeys(expandedDevices, key: SidebarDefaults.expandedDevicesKey)
    }

    private func seedExpandedPinnedIfNeeded() {
        guard expandedFavorites.isEmpty else { return }
        for group in appState.sidebarPinnedGroups {
            expandedFavorites.insert(SidebarExpansionKey.host(group.host))
        }
        if !expandedFavorites.isEmpty {
            SidebarDefaults.saveExpansionKeys(expandedFavorites, key: SidebarDefaults.expandedFavoritesKey)
        }
    }

    private func autoExpandConnectedDevicesIfNeeded() {
        var changed = false
        for ip in appState.remoteDeviceIPs {
            let deviceKey = TrafficDeviceCatalog.deviceKey(
                forRemoteIP: ip,
                sessions: appState.sessions.sessions.filter(SessionDisplayRules.shouldCapture)
            )
            if expandedDevices.insert(deviceKey).inserted {
                changed = true
            }
        }
        if changed {
            isAllSectionExpanded = true
            UserDefaults.standard.set(true, forKey: SidebarDefaults.allSectionExpandedKey)
            SidebarDefaults.saveExpansionKeys(expandedDevices, key: SidebarDefaults.expandedDevicesKey)
        }
    }

    /// Expands pinned rows automatically once endpoints appear (fixes baseURL key drift).
    private func autoExpandPinnedGroupsWithTraffic() {
        var changed = false
        for group in appState.sidebarPinnedGroups where !group.endpoints.isEmpty {
            let key = SidebarExpansionKey.host(group.host)
            if expandedFavorites.insert(key).inserted {
                changed = true
            }
        }
        if changed {
            SidebarDefaults.saveExpansionKeys(expandedFavorites, key: SidebarDefaults.expandedFavoritesKey)
        }
    }

    private var hasActiveFilter: Bool {
        appState.hasActiveTrafficFilter
    }

    private var activeFilterLabel: String? {
        if let endpoint = appState.selectedEndpointKey { return endpoint }
        if let domain = appState.selectedDomainFilter {
            if let device = appState.selectedDeviceFilter,
               let name = appState.trafficDeviceGroups.first(where: { $0.id == device })?.displayName {
                return "\(name) · \(domain)"
            }
            return "Domain: \(domain)"
        }
        if let device = appState.selectedDeviceFilter,
           let name = appState.trafficDeviceGroups.first(where: { $0.id == device })?.displayName {
            return "Device: \(name)"
        }
        if appState.showFavoritesOnly { return "Favorites filter" }
        return nil
    }

    private func isDeviceSelected(_ device: TrafficDeviceGroup) -> Bool {
        guard appState.selectedEndpointKey == nil else { return false }
        guard appState.selectedDomainFilter == nil else { return false }
        return appState.selectedDeviceFilter == device.id
    }

    private func isDomainSelected(_ group: APIBaseGroup, deviceKey: String?) -> Bool {
        guard appState.selectedEndpointKey == nil else { return false }
        guard let domain = appState.selectedDomainFilter else { return false }
        guard domain.caseInsensitiveCompare(group.host) == .orderedSame else { return false }
        if let deviceKey {
            return appState.selectedDeviceFilter == deviceKey
        }
        return appState.selectedDeviceFilter == nil
    }

    private func selectDeviceFromSidebar(_ device: TrafficDeviceGroup) {
        appState.selectDevice(device.id)
        expandedDevices.insert(device.id)
        SidebarDefaults.saveExpansionKeys(expandedDevices, key: SidebarDefaults.expandedDevicesKey)
    }

    private func selectDomainFromSidebar(_ group: APIBaseGroup, pinned: Bool, deviceKey: String? = nil) {
        if pinned, group.endpoints.isEmpty {
            // Expand only — don't apply an empty domain filter that hides all rows.
        } else {
            appState.selectDomain(group.host, deviceKey: pinned ? nil : deviceKey)
        }
        if pinned {
            let key = SidebarExpansionKey.host(group.host)
            expandedFavorites.insert(key)
            SidebarDefaults.saveExpansionKeys(expandedFavorites, key: SidebarDefaults.expandedFavoritesKey)
        } else if let deviceKey {
            let key = SidebarExpansionKey.deviceDomain(deviceID: deviceKey, host: group.host)
            expandedDomains.insert(key)
            expandedDevices.insert(deviceKey)
            SidebarDefaults.saveExpansionKeys(expandedDomains, key: SidebarDefaults.expandedDomainsKey)
            SidebarDefaults.saveExpansionKeys(expandedDevices, key: SidebarDefaults.expandedDevicesKey)
        }
    }

    private func methodColor(_ method: String) -> Color {
        HTTPMethodStyle.color(for: method)
    }
}

private enum SidebarExpansionKey {
    static func host(_ host: String) -> String {
        host.lowercased()
    }

    static func deviceDomain(deviceID: String, host: String) -> String {
        "\(deviceID)|\(host.lowercased())"
    }
}

private enum SidebarDefaults {
    static let expandedFavoritesKey = "ShubhranshProxy.sidebar.expandedFavorites"
    static let expandedDevicesKey = "ShubhranshProxy.sidebar.expandedDevices"
    static let expandedDomainsKey = "ShubhranshProxy.sidebar.expandedDomains"
    static let allSectionExpandedKey = "ShubhranshProxy.sidebar.allSectionExpanded"

    static func loadExpansionKeys(_ key: String) -> Set<String> {
        let raw = UserDefaults.standard.stringArray(forKey: key) ?? []
        return Set(raw.map(normalizeExpansionKey))
    }

    static func saveExpansionKeys(_ value: Set<String>, key: String) {
        UserDefaults.standard.set(Array(value).sorted(), forKey: key)
    }

    private static func normalizeExpansionKey(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("://"), let host = URL(string: trimmed)?.host {
            return host.lowercased()
        }
        return trimmed.lowercased()
    }
}

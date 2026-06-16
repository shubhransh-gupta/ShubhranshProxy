//
//  DomainsSidebarView.swift
//  ShubhranshProxy — Proxyman-style sidebar sections
//

import SwiftUI

struct DomainsSidebarView: View {
    let section: SidebarSection
    @Environment(AppState.self) private var appState
    @State private var sidebarSearch = ""
    @State private var pinDomainInput = ""
    @State private var expandedKeys: Set<String> = SidebarDefaults.loadAllExpansionKeys()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if section == .pinned {
                pinDomainBar
                Divider()
            }
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
    }

    private var header: some View {
        HStack {
            Text(section.rawValue)
                .font(.headline)
            Spacer()
            if appState.hasActiveTrafficFilter {
                Button("Clear") { appState.clearTrafficFilters() }
                    .font(.caption)
                    .buttonStyle(.link)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var pinDomainBar: some View {
        HStack(spacing: 8) {
            TextField("example.com or full URL", text: $pinDomainInput)
                .textFieldStyle(.roundedBorder)
                .onSubmit { submitPin() }
            Button("Pin") { submitPin() }
                .disabled(pinDomainInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var sidebarList: some View {
        List {
            switch section {
            case .pinned:
                pinnedSection
            case .devices:
                devicesSection
            case .domains:
                domainsSection
            }
        }
        .listStyle(.sidebar)
    }

    @ViewBuilder
    private var pinnedSection: some View {
        if filteredPinnedGroups.isEmpty {
            emptyState(
                title: "No pinned domains yet",
                detail: "Enter a domain above, or right-click a request and choose Pin domain."
            )
        } else {
            Section {
                ForEach(filteredPinnedGroups) { group in
                    pinnedGroupRow(group)
                }
            } header: {
                Label("Your pins", systemImage: "star.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textCase(nil)
            }
        }
    }

    @ViewBuilder
    private var devicesSection: some View {
        let devices = filteredDeviceGroups
        if devices.isEmpty {
            emptyState(
                title: "No devices connected yet.",
                detail: appState.isRunning && appState.acceptsRemoteDeviceConnections
                    ? appState.deviceProxySetupHint
                    : "Start capture to see devices here."
            )
        } else {
            Section {
                ForEach(devices) { device in
                    deviceRow(device)
                }
            } header: {
                Label("Connected devices", systemImage: "ipad.and.iphone")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textCase(nil)
            }
        }
    }

    @ViewBuilder
    private var domainsSection: some View {
        let groups = filteredDomainGroups
        if groups.isEmpty {
            emptyState(
                title: "No domains yet.",
                detail: appState.isRunning
                    ? "Browse the web or use an app to populate domains."
                    : "Start capture to see domains here."
            )
        } else {
            Section {
                ForEach(groups) { group in
                    domainGroupRow(group)
                }
            } header: {
                Label("All domains", systemImage: "globe")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textCase(nil)
            }
        }
    }

    private func emptyState(title: String, detail: String) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 4)
        }
    }

    private func pinnedGroupRow(_ group: APIBaseGroup) -> some View {
        let key = SidebarExpansionKey.host(group.host)
        return DisclosureGroup(isExpanded: expansionBinding(key)) {
            if group.endpoints.isEmpty {
                Text("Waiting for traffic to this domain…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
            } else {
                ForEach(group.endpoints) { endpoint in
                    endpointRow(endpoint)
                }
            }
        } label: {
            selectableLabel(isSelected: isDomainSelected(group, deviceKey: nil)) {
                pinnedGroupLabelContent(group)
            } onSelect: {
                selectDomainFromSidebar(group, pinned: true)
            }
        }
        .contextMenu { domainContextMenu(for: group) }
    }

    private func domainGroupRow(_ group: APIBaseGroup) -> some View {
        let key = SidebarExpansionKey.host(group.host)
        return DisclosureGroup(isExpanded: expansionBinding(key)) {
            if group.endpoints.isEmpty {
                tunnelOnlyHint(group)
            } else {
                ForEach(group.endpoints) { endpoint in
                    endpointRow(endpoint)
                }
                if group.tunnelRequestCount > 0 {
                    tunnelOnlyHint(group)
                        .padding(.top, 4)
                }
            }
        } label: {
            selectableLabel(isSelected: isDomainSelected(group, deviceKey: nil)) {
                domainGroupLabelContent(group)
            } onSelect: {
                selectDomainFromSidebar(group, pinned: false)
            }
        }
        .contextMenu { domainContextMenu(for: group) }
    }

    private func deviceRow(_ device: TrafficDeviceGroup) -> some View {
        DisclosureGroup(isExpanded: expansionBinding(device.id)) {
            if device.domainGroups.isEmpty {
                Text(deviceWaitingText(device))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
            } else {
                ForEach(filterDomains(device.domainGroups), id: \.baseURL) { group in
                    let domainKey = SidebarExpansionKey.deviceDomain(deviceID: device.id, host: group.host)
                    DisclosureGroup(isExpanded: expansionBinding(domainKey)) {
                        ForEach(group.endpoints) { endpoint in
                            endpointRow(endpoint, deviceKey: device.id)
                        }
                    } label: {
                        selectableLabel(isSelected: isDomainSelected(group, deviceKey: device.id)) {
                            deviceDomainLabelContent(group, deviceKey: device.id)
                        } onSelect: {
                            selectDomainFromSidebar(group, pinned: false, deviceKey: device.id)
                        }
                    }
                    .padding(.leading, 8)
                    .contextMenu { domainContextMenu(for: group, deviceKey: device.id) }
                }
            }
        } label: {
            selectableLabel(isSelected: isDeviceSelected(device)) {
                deviceGroupLabelContent(device)
            } onSelect: {
                selectDeviceFromSidebar(device)
            }
        }
    }

    private func selectableLabel<Content: View>(
        isSelected: Bool,
        @ViewBuilder content: () -> Content,
        onSelect: @escaping () -> Void
    ) -> some View {
        Button(action: onSelect) {
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
    }

    private func expansionBinding(_ key: String) -> Binding<Bool> {
        Binding(
            get: { expandedKeys.contains(key) },
            set: { expanded in
                if expanded {
                    expandedKeys.insert(key)
                } else {
                    expandedKeys.remove(key)
                }
                SidebarDefaults.saveAllExpansionKeys(expandedKeys)
            }
        )
    }

    private func submitPin() {
        let trimmed = pinDomainInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if trimmed.contains("/") {
            appState.pinEndpointURL(trimmed)
        } else {
            appState.pinDomain(trimmed)
        }
        pinDomainInput = ""
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
    }

    @ViewBuilder
    private func tunnelOnlyHint(_ group: APIBaseGroup) -> some View {
        if group.tunnelRequestCount > 0 {
            Text(
                group.endpoints.allSatisfy({ $0.method == "CONNECT" })
                    ? "Encrypted HTTPS only — right-click domain → Decrypt HTTPS, or add \(group.host) under SSL Proxy."
                    : "\(group.tunnelRequestCount) additional encrypted tunnel\(group.tunnelRequestCount == 1 ? "" : "s")."
            )
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.leading, 4)
        }
    }

    private func domainGroupLabelContent(_ group: APIBaseGroup) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(group.host)
                    .font(.callout)
                    .lineLimit(1)
                Text(group.apiSummaryLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isDomainSelected(group, deviceKey: nil) {
                Image(systemName: "line.3.horizontal.decrease.circle.fill")
                    .font(.caption)
            }
        }
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
            }
        }
    }

    private func deviceDomainLabelContent(_ group: APIBaseGroup, deviceKey: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(group.host)
                    .font(.callout)
                    .lineLimit(1)
                Text(group.apiSummaryLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isDomainSelected(group, deviceKey: deviceKey) {
                Image(systemName: "line.3.horizontal.decrease.circle.fill")
                    .font(.caption)
            }
        }
    }

    private func deviceSubtitle(_ device: TrafficDeviceGroup) -> String {
        if device.sessionCount == 0,
           appState.remoteDeviceIPs.contains(where: { device.id.hasSuffix($0) }) {
            return "Connected · waiting for requests"
        }
        return "\(device.domainGroups.count) hosts · \(device.sessionCount) requests"
    }

    private func deviceWaitingText(_ device: TrafficDeviceGroup) -> String {
        if appState.remoteDeviceIPs.contains(where: { device.id.hasSuffix($0) }) {
            return "Connected — waiting for requests…"
        }
        return "No traffic from this device yet."
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
        if appState.features.favorites.isFavorite(group.host) {
            Button("Unpin domain") {
                appState.unpinDomain(group.host)
            }
        } else {
            Button("Pin domain") {
                appState.pinDomain(group.host)
            }
        }
    }

    private func endpointRow(_ endpoint: APIEndpointSummary, deviceKey: String? = nil) -> some View {
        let isSelected = appState.selectedEndpointKey == endpoint.endpointKey
        return Button {
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
        .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
        .contextMenu { endpointContextMenu(endpoint) }
    }

    @ViewBuilder
    private func endpointContextMenu(_ endpoint: APIEndpointSummary) -> some View {
        Button("Filter requests") { appState.selectEndpoint(endpoint) }
        if appState.features.favorites.isFavorite(endpoint.host) {
            Button("Unpin domain") { appState.unpinDomain(endpoint.host) }
        } else {
            Button("Pin domain") { appState.pinDomain(endpoint.host) }
        }
        if appState.features.favorites.isFavoriteEndpoint(endpoint.fullURL) {
            Button("Unpin endpoint") { appState.features.favorites.unpinEndpoint(endpoint.fullURL); appState.notifyFavoritesChanged() }
        } else {
            Button("Pin endpoint") { appState.pinEndpointURL(endpoint.fullURL) }
        }
        Button("Map Local…") {
            appState.presentMappingTools(prefill: MappingToolsPrefill(mode: .mapLocal, matchURL: endpoint.fullURL))
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
                Text("\(appState.rawVisibleSessionCount)")
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
        let groups = appState.trafficDeviceGroups
        guard !sidebarSearch.isEmpty else { return groups }
        return groups.compactMap { device in
            let domains = filterGroups(device.domainGroups)
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

    private var filteredDomainGroups: [APIBaseGroup] {
        filterGroups(appState.apiBaseGroups)
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
                endpoints: endpoints,
                tunnelRequestCount: group.tunnelRequestCount
            )
        }
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
        appState.selectedEndpointKey == nil
            && appState.selectedDomainFilter == nil
            && appState.selectedDeviceFilter == device.id
    }

    private func isDomainSelected(_ group: APIBaseGroup, deviceKey: String?) -> Bool {
        guard appState.selectedEndpointKey == nil,
              let domain = appState.selectedDomainFilter,
              domain.caseInsensitiveCompare(group.host) == .orderedSame else {
            return false
        }
        if let deviceKey {
            return appState.selectedDeviceFilter == deviceKey
        }
        return appState.selectedDeviceFilter == nil
    }

    private func selectDeviceFromSidebar(_ device: TrafficDeviceGroup) {
        appState.selectDevice(device.id)
    }

    private func selectDomainFromSidebar(_ group: APIBaseGroup, pinned: Bool, deviceKey: String? = nil) {
        if !(pinned && group.endpoints.isEmpty) {
            appState.selectDomain(group.host, deviceKey: pinned ? nil : deviceKey)
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
    static let allExpandedKey = "ShubhranshProxy.sidebar.expandedKeys"

    static func loadAllExpansionKeys() -> Set<String> {
        let unified = UserDefaults.standard.stringArray(forKey: allExpandedKey) ?? []
        if !unified.isEmpty {
            return Set(unified)
        }
        // Migrate legacy keys into one store.
        let merged = loadExpansionKeys("ShubhranshProxy.sidebar.expandedFavorites")
            .union(loadExpansionKeys("ShubhranshProxy.sidebar.expandedDevices"))
            .union(loadExpansionKeys("ShubhranshProxy.sidebar.expandedDomains"))
        if !merged.isEmpty {
            saveAllExpansionKeys(merged)
        }
        return merged
    }

    static func saveAllExpansionKeys(_ value: Set<String>) {
        UserDefaults.standard.set(Array(value).sorted(), forKey: allExpandedKey)
    }

    private static func loadExpansionKeys(_ key: String) -> Set<String> {
        Set((UserDefaults.standard.stringArray(forKey: key) ?? []).map { $0.lowercased() })
    }
}

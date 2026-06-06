//
//  CaptureWorkspaceView.swift
//  ShubhranshProxy — Proxyman-style: request list on top, inspector below.
//  Created by Shubhransh Gupta
//

import SwiftUI

struct CaptureWorkspaceView: View {
    @Environment(AppState.self) private var appState
    @State private var showProxySettings = false
    @State private var isInspectorExpanded = InspectorLayout.loadExpanded()
    @State private var inspectorHeight = InspectorLayout.loadHeight()
    @State private var resizeDragStartHeight: CGFloat?

    var body: some View {
        @Bindable var state = appState
        VStack(spacing: 0) {
            workspaceTitleBar(activeView: $state.activeCaptureView)
            Divider()

            switch state.activeCaptureView {
            case .sessions, .favorites:
                requestListAndInspector
            case .ssl:
                ScrollView {
                    SSLProxySettingsView(appState: state)
                        .padding()
                }
            case .tools:
                NavigationStack {
                    ToolsHubView(appState: state)
                        .toolbar {
                            ToolbarItem(placement: .navigation) {
                                Button {
                                    appState.returnToCaptureHome()
                                } label: {
                                    Label("Capture", systemImage: "list.bullet.rectangle")
                                }
                            }
                        }
                }
            }
        }
        .sheet(isPresented: $showProxySettings) {
            ProxySettingsSheet(appState: state)
                .frame(minWidth: 420, minHeight: 320)
        }
        .onChange(of: state.activeCaptureView) { _, newView in
            if newView == .favorites {
                appState.prepareFavoritesView()
            }
        }
    }

    private var requestListAndInspector: some View {
        VStack(spacing: 0) {
            captureHealthBanner
            captureStatusBanner
            if appState.showFavoritesOnly {
                favoritesFilterBanner
            }
            contentFilterBar
            Divider()
            sessionFilterBar
            Divider()

            ZStack {
                SessionTableView()
                    .layoutPriority(1)

                if appState.sessionsForTable.isEmpty {
                    favoritesEmptyState
                }
            }

            inspectorSplitter

            if isInspectorExpanded {
                SessionInspectorView(selectedSessionId: appState.sessions.selectedSessionId)
                    .frame(height: inspectorHeight)
            }
        }
    }

    @ViewBuilder
    private var captureStatusBanner: some View {
        if appState.isRunning, !appState.sessions.isRecording {
            HStack(spacing: 8) {
                Image(systemName: "record.circle")
                    .foregroundStyle(.red)
                Text("Recording is OFF — new requests will not appear. Turn Record back on in the toolbar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Record") { appState.sessions.isRecording = true }
                    .font(.caption)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.red.opacity(0.1))
        } else if appState.isRunning,
                  appState.enableSystemProxy,
                  !appState.macSystemProxyIsConfigured {
            HStack(spacing: 8) {
                Image(systemName: "network.slash")
                    .foregroundStyle(.orange)
                Text("Mac Wi‑Fi proxy is NOT configured — no Mac traffic will be captured. Click Retry routing and enter your password.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Spacer()
                Button("Retry routing") {
                    Task { await appState.configureSystemProxyRouting() }
                }
                .font(.caption)
                Button("Network settings") {
                    appState.openMacNetworkProxySettings()
                }
                .font(.caption)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.orange.opacity(0.15))
        } else if appState.hiddenSessionCount > 0 {
            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .foregroundStyle(.orange)
                Text("\(appState.hiddenSessionCount) request\(appState.hiddenSessionCount == 1 ? "" : "s") hidden by sidebar or table filters.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Clear filters") { appState.clearTrafficFilters() }
                    .font(.caption)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.orange.opacity(0.1))
        } else if appState.isRunning,
                  appState.rawVisibleSessionCount == 0,
                  !appState.tls.sslSettings.interceptAllHosts,
                  appState.tls.sslProxyingEnabled {
            HStack(spacing: 8) {
                Image(systemName: "lock.shield")
                    .foregroundStyle(.secondary)
                Text("Selective SSL is on — only listed hosts are fully decrypted. Other HTTPS appears as CONNECT tunnels. Add hosts under SSL Proxy.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Spacer()
                Button("SSL") { appState.activeCaptureView = .ssl }
                    .font(.caption)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.secondary.opacity(0.08))
        }
    }

    @ViewBuilder
    private var favoritesEmptyState: some View {
        if appState.showFavoritesOnly || appState.selectedDomainFilter != nil || appState.selectedDeviceFilter != nil {
            ContentUnavailableView {
                Label("No matching requests", systemImage: "star.slash")
            } description: {
                if appState.showFavoritesOnly {
                    Text("Pin domains or endpoints from the sidebar or session list. Traffic from pinned hosts appears here.")
                } else if let domain = appState.selectedDomainFilter {
                    Text("No captured requests for \(domain) yet.")
                } else {
                    Text("Try clearing filters or capture more traffic.")
                }
            } actions: {
                if appState.hasActiveTrafficFilter {
                    Button("Clear filters") {
                        appState.clearTrafficFilters()
                    }
                }
            }
        }
    }

    private var favoritesFilterBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "star.fill")
                .foregroundStyle(.yellow)
            Text("Showing pinned / favorite traffic — \(appState.sessionsForTable.count) request\(appState.sessionsForTable.count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Clear") {
                appState.clearTrafficFilters()
            }
            .font(.caption)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.yellow.opacity(0.1))
    }

    private var inspectorSplitter: some View {
        HStack(spacing: 8) {
            Capsule()
                .fill(Color.secondary.opacity(0.35))
                .frame(width: 36, height: 4)

            Text("Inspector")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            Spacer()

            if isInspectorExpanded {
                Text("\(Int(inspectorHeight)) pt")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }

            Button(action: toggleInspectorExpanded) {
                Image(systemName: isInspectorExpanded ? "chevron.down" : "chevron.up")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 20)
            }
            .buttonStyle(.plain)
            .help(isInspectorExpanded ? "Collapse inspector" : "Expand inspector")
        }
        .padding(.horizontal, 12)
        .frame(height: isInspectorExpanded ? InspectorLayout.splitterHeight : InspectorLayout.collapsedBarHeight)
        .background(.bar)
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: toggleInspectorExpanded)
        .gesture(inspectorResizeGesture)
    }

    private var inspectorResizeGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                guard isInspectorExpanded else { return }
                if resizeDragStartHeight == nil {
                    resizeDragStartHeight = inspectorHeight
                }
                guard let start = resizeDragStartHeight else { return }
                inspectorHeight = InspectorLayout.clamp(start - value.translation.height)
            }
            .onEnded { _ in
                resizeDragStartHeight = nil
                InspectorLayout.saveHeight(inspectorHeight)
            }
    }

    private func toggleInspectorExpanded() {
        isInspectorExpanded.toggle()
        InspectorLayout.saveExpanded(isInspectorExpanded)
    }

    @ViewBuilder
    private var captureHealthBanner: some View {
        if let warning = appState.captureWarning {
            let isDeviceHint = warning.contains("iPhone/Android") || warning.contains("Wi‑Fi IP") || warning.contains("iPhone Wi‑Fi") || warning.contains("Set iPhone") || warning.contains("Mobile device connected")
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(warning)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                Spacer()
                if warning.contains("Certificate Trust") || warning.contains("no API traffic") {
                    Button("SSL & cert") { appState.activeCaptureView = .ssl }
                        .font(.caption)
                } else                 if !isDeviceHint {
                    if !appState.macSystemProxyIsConfigured, appState.enableSystemProxy {
                        Button("Retry routing") {
                            Task { await appState.configureSystemProxyRouting() }
                        }
                        .font(.caption)
                        Button("Network settings") {
                            appState.openMacNetworkProxySettings()
                        }
                        .font(.caption)
                    } else if !appState.enableSystemProxy {
                        Button("Route macOS traffic") {
                            appState.setEnableSystemProxy(true)
                            Task { await appState.configureSystemProxyRouting() }
                        }
                        .font(.caption)
                    } else {
                        Button("Retry routing") {
                            Task { await appState.configureSystemProxyRouting() }
                        }
                        .font(.caption)
                    }
                }
                Button("Proxy settings") { showProxySettings = true }
                    .font(.caption)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.orange.opacity(0.12))
        } else if appState.isRunning,
                  appState.tls.sslProxyingEnabled,
                  !appState.tls.rootCertificateTrusted,
                  let ssl = appState.tls.lastTrustError {
            HStack(spacing: 8) {
                Image(systemName: "lock.trianglebadge.exclamationmark")
                    .foregroundStyle(.orange)
                Text(ssl)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("SSL") { appState.activeCaptureView = .ssl }
                    .font(.caption)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.orange.opacity(0.12))
        }
    }

    private func workspaceTitleBar(activeView: Binding<CaptureView>) -> some View {
        HStack(spacing: 12) {
            Picker("View", selection: activeView) {
                ForEach(CaptureView.allCases) { view in
                    Label(view.rawValue, systemImage: view.systemImage).tag(view)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 400)

            if appState.isRunning {
                HStack(spacing: 6) {
                    Circle().fill(.green).frame(width: 8, height: 8)
                    Text(appState.compactCaptureStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .help(appState.detailedCaptureStatus)
                }
            }

            Spacer()

            Text("\(appState.sessionsForTable.count) requests")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            Button {
                showProxySettings = true
            } label: {
                Label("Proxy settings", systemImage: "gearshape")
            }
            .labelStyle(.iconOnly)

            Button(action: toggleInspectorExpanded) {
                Label(
                    isInspectorExpanded ? "Hide inspector" : "Show inspector",
                    systemImage: isInspectorExpanded ? "rectangle.bottomhalf.inset.filled" : "rectangle.tophalf.inset.filled"
                )
            }
            .labelStyle(.iconOnly)
            .help(isInspectorExpanded ? "Collapse inspector panel" : "Expand inspector panel")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var contentFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(SessionContentFilter.allCases) { filter in
                    let isSelected = appState.sessionContentFilter == filter
                    Button {
                        appState.sessionContentFilter = filter
                    } label: {
                        Text(filter.label)
                            .font(.caption.weight(isSelected ? .semibold : .regular))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                isSelected
                                    ? Color.accentColor.opacity(0.2)
                                    : Color.secondary.opacity(0.12)
                            )
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .background(.bar.opacity(0.5))
    }

    private var sessionFilterBar: some View {
        @Bindable var sessions = appState.sessions
        return HStack(spacing: 8) {
            TextField("Filter URL", text: $sessions.searchText)
                .textFieldStyle(.roundedBorder)
            TextField("Method", text: $sessions.filterMethod)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 72)
            TextField("Status", text: $sessions.filterStatusCode)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 56)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

private enum InspectorLayout {
    static let expandedKey = "ShubhranshProxy.inspector.expanded"
    static let heightKey = "ShubhranshProxy.inspector.height"
    static let defaultHeight: CGFloat = 300
    static let minHeight: CGFloat = 160
    static let maxHeight: CGFloat = 560
    static let splitterHeight: CGFloat = 24
    static let collapsedBarHeight: CGFloat = 28

    static func loadExpanded() -> Bool {
        UserDefaults.standard.object(forKey: expandedKey) as? Bool ?? true
    }

    static func loadHeight() -> CGFloat {
        let stored = CGFloat(UserDefaults.standard.double(forKey: heightKey))
        return stored > 0 ? clamp(stored) : defaultHeight
    }

    static func saveExpanded(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: expandedKey)
    }

    static func saveHeight(_ value: CGFloat) {
        UserDefaults.standard.set(Double(clamp(value)), forKey: heightKey)
    }

    static func clamp(_ value: CGFloat) -> CGFloat {
        min(maxHeight, max(minHeight, value))
    }
}

struct ToolsHubView: View {
    @Bindable var appState: AppState

    var body: some View {
        List {
            Section("Intercept") {
                NavigationLink {
                    BreakpointsEditorView(appState: appState)
                } label: {
                    Label("Breakpoints", systemImage: "pause.circle")
                }
                NavigationLink {
                    RewriteRulesEditorView(appState: appState)
                } label: {
                    Label("Rewrite", systemImage: "arrow.triangle.2.circlepath")
                }
                NavigationLink {
                    BlockListEditorView(appState: appState)
                } label: {
                    Label("Block list", systemImage: "nosign")
                }
            }
            Section("Simulate") {
                Button {
                    appState.presentMappingTools()
                } label: {
                    Label("Map Local & Map Remote", systemImage: "arrow.triangle.swap")
                }
                Button {
                    appState.presentAllMappedURLs()
                } label: {
                    HStack {
                        Label("All Mapped URLs", systemImage: "list.bullet.rectangle")
                        Spacer()
                        if appState.mappedRuleCount > 0 {
                            Text("\(appState.mappedRuleCount)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                NavigationLink {
                    ThrottleSettingsView(appState: appState)
                } label: {
                    Label("Throttling", systemImage: "speedometer")
                }
                NavigationLink {
                    RequestComposerView(appState: appState)
                } label: {
                    Label("Composer", systemImage: "paperplane")
                }
            }
            Section("Analyze") {
                NavigationLink {
                    SessionDiffView()
                } label: {
                    Label("Diff sessions", systemImage: "arrow.left.arrow.right")
                }
                Button("Export HAR") { appState.exportHAR() }
                Button("Import HAR…") { appState.importHAR(replace: false) }
            }
        }
        .listStyle(.inset)
    }
}

struct ProxySettingsSheet: View {
    @Bindable var appState: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Proxy settings")
                .font(.title2.bold())

            Form {
                Section("Listen") {
                    HStack {
                        TextField("Host", text: $appState.listenHost)
                            .disabled(appState.isRunning)
                        TextField("Port", value: $appState.listenPort, format: .number)
                            .frame(width: 72)
                            .disabled(appState.isRunning)
                    }
                    if appState.isRunning {
                        Text("Stop capture before changing listen address.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        HStack(spacing: 8) {
                            Button("All interfaces (devices)") {
                                appState.listenHost = "0.0.0.0"
                            }
                            .buttonStyle(.bordered)
                            .disabled(appState.listenHost == "0.0.0.0")

                            Button("This Mac only") {
                                appState.listenHost = "127.0.0.1"
                            }
                            .buttonStyle(.bordered)
                            .disabled(appState.listenHost == "127.0.0.1")
                        }
                    }
                    if appState.acceptsRemoteDeviceConnections {
                        if appState.lanInterfaceAddresses.isEmpty {
                            Text("No LAN IP found — connect Wi‑Fi so your phone can reach this Mac.")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        } else {
                            ForEach(appState.lanInterfaceAddresses) { iface in
                                LabeledContent("\(iface.name) (iPhone proxy)") {
                                    Text("\(iface.address):\(appState.listenPort)")
                                        .font(.body.monospaced())
                                        .textSelection(.enabled)
                                }
                            }
                        }
                        Text(appState.deviceProxySetupHint)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Listen Host 127.0.0.1 blocks iPhone/Android. Use 0.0.0.0 to capture from devices on the same Wi‑Fi.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                Section("System proxy") {
                    Toggle("Route macOS traffic", isOn: Binding(
                        get: { appState.enableSystemProxy },
                        set: { enabled in
                            appState.setEnableSystemProxy(enabled)
                            if enabled, appState.isRunning {
                                Task { await appState.configureSystemProxyRouting() }
                            }
                        }
                    ))
                    Text("macOS apps use \(appState.macProxyEndpoint) — not the bind address above.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Toggle("Restore macOS Wi‑Fi/Ethernet proxy when stopping or quitting", isOn: Binding(
                        get: { appState.restoreSystemProxyOnExit },
                        set: { appState.setRestoreSystemProxyOnExit($0) }
                    ))
                    .disabled(appState.isRunning)
                    Text("When enabled, ShubhranshProxy turns off the Mac system proxy on Stop and when you quit the app so internet works normally again. iPhone Wi‑Fi proxy must be turned off manually in Settings.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Done") {
                    appState.persistListenSettings()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
    }
}

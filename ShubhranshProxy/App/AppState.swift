//
//  AppState.swift
//  ShubhranshProxy
//  Created by Shubhransh Gupta
//

import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class AppState {
    private static let listenHostKey = "ShubhranshProxy.listenHost"
    private static let listenPortKey = "ShubhranshProxy.listenPort"
    private static let listenHostDeviceMigrationKey = "ShubhranshProxy.listenHost.deviceMigration.v1"
    private static let wasCapturingOnExitKey = "ShubhranshProxy.wasCapturingOnExit"

    var listenHost = HTTPProxyConfiguration.default.listenHost
    var listenPort = HTTPProxyConfiguration.default.listenPort
    var lastError: String?
    /// On by default — Start routes macOS traffic here (admin password only when settings first need to change).
    var enableSystemProxy = UserDefaults.standard.object(forKey: "ShubhranshProxy.enableSystemProxy") as? Bool ?? true
    /// When false, Stop keeps macOS proxy settings (no admin password). Quit still restores by default.
    var restoreSystemProxyOnStop = UserDefaults.standard.object(forKey: "ShubhranshProxy.restoreSystemProxyOnStop") as? Bool ?? true
    var restoreSystemProxyOnQuit = UserDefaults.standard.object(forKey: "ShubhranshProxy.restoreSystemProxyOnQuit") as? Bool ?? true
    private(set) var systemProxyActive = false
    var captureWarning: String?
    var selectedURLFilter: String?

    let sessions = SessionStore()
    let tls = TLSManager()
    let features = FeatureRegistry()
    let remoteClients = RemoteClientTracker()

    private let proxyEngine = ProxyEngine()
    private let rulesMailbox = MapLocalRulesMailbox()
    private let mapRemoteMailbox = MapRemoteRulesMailbox()
    private let sslMailbox = SSLProxySettingsMailbox()
    private let certMailbox = CertificateMailbox()
    private let certIssuer = SynchronousCertificateIssuer()
    private let blockListMailbox = BlockListMailbox()
    private let rewriteMailbox = RewriteRulesMailbox()
    private let throttleMailbox = ThrottleMailbox()
    private let breakpointMailbox = BreakpointMailbox()

    // Throttled sidebar catalog — avoids rebuilding trees on every SwiftUI body pass.
    private var catalogSessionCount = -1
    private var catalogRemoteIPSignature = ""
    private var catalogFavoriteSignature = ""
    private var cachedTrafficDeviceGroups: [TrafficDeviceGroup] = []
    private var cachedApiBaseGroups: [APIBaseGroup] = []
    private var cachedSidebarPinnedGroups: [APIBaseGroup] = []
    /// Bumped when captured traffic changes so sidebar lists refresh without AttributeGraph cycles.
    private(set) var trafficCatalogRevision = 0

    var isRunning = false
    var sidebarSection: SidebarSection = SidebarSection.loadPersisted()
    var activeCaptureView: CaptureView = .sessions
    /// Set after a successful macOS proxy restore so Stop + Quit do not prompt twice.
    private var systemProxyRestoredThisSession = false
    var selectedDomainFilter: String?
    var selectedDeviceFilter: String?
    var selectedBaseURLFilter: String?
    var selectedEndpointKey: String?
    /// Updated on AppState so SwiftUI refreshes the Devices sidebar when phones connect.
    private(set) var remoteDeviceIPs: [String] = []
    var showFavoritesOnly: Bool { activeCaptureView == .favorites }
    var mappingToolsPrefill: MappingToolsPrefill?
    var showMappingToolsSheet = false
    var sessionContentFilter: SessionContentFilter = .all

    init() {
        loadListenSettings()
        migrateListenHostForDeviceAccessIfNeeded()
        ensureCertificateIssuerLoaded()
        syncMappingMailboxes()
        syncSSLMailboxes()
        syncFeatureMailboxes()
        tls.refreshInstallationState()
        syncSSLMailboxes()
        features.breakpoints.attach(mailbox: breakpointMailbox)
        migrateRestoreProxyDefaultsIfNeeded()
        LegacyBundledHostCleanup.applyIfNeeded(favorites: features.favorites, tls: tls)
        recoverFromInterruptedSystemProxyIfNeeded()
        sessions.onSessionsChanged = { [weak self] in
            self?.invalidateTrafficCatalogCache()
        }
        sessions.clearPersistedCaptureData()
    }

    private func migrateRestoreProxyDefaultsIfNeeded() {
        let migrationKey = "ShubhranshProxy.restoreSystemProxy.defaultsMigration.v1"
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }
        if UserDefaults.standard.object(forKey: "ShubhranshProxy.restoreSystemProxyOnStop") == nil {
            restoreSystemProxyOnStop = true
            UserDefaults.standard.set(true, forKey: "ShubhranshProxy.restoreSystemProxyOnStop")
        }
        if UserDefaults.standard.object(forKey: "ShubhranshProxy.restoreSystemProxyOnQuit") == nil {
            restoreSystemProxyOnQuit = true
            UserDefaults.standard.set(true, forKey: "ShubhranshProxy.restoreSystemProxyOnQuit")
        }
        UserDefaults.standard.set(true, forKey: migrationKey)
    }

    /// If the previous run crashed, macOS Wi‑Fi/Ethernet may still point here — restore on Stop/Quit, not on launch.
    private func recoverFromInterruptedSystemProxyIfNeeded() {
        guard UserDefaults.standard.bool(forKey: Self.wasCapturingOnExitKey) else { return }
        UserDefaults.standard.set(false, forKey: Self.wasCapturingOnExitKey)

        let proxyHost = HTTPProxyConfiguration.systemProxyHost
        let stillRouted = SystemProxyManager.isRoutingThroughApp(host: proxyHost, port: listenPort)
        let hasSnapshots = SystemProxyManager.hasPersistedRestoreSnapshots()
        systemProxyActive = stillRouted

        if stillRouted || hasSnapshots {
            captureWarning =
                "ShubhranshProxy was interrupted while capturing. macOS Wi‑Fi proxy may still be active — close the app or press Stop to restore."
        }
    }

    private func markCaptureSessionActive(_ active: Bool) {
        UserDefaults.standard.set(active, forKey: Self.wasCapturingOnExitKey)
    }

    func loadListenSettings() {
        if let savedHost = UserDefaults.standard.string(forKey: Self.listenHostKey), !savedHost.isEmpty {
            listenHost = savedHost
        }
        let savedPort = UserDefaults.standard.integer(forKey: Self.listenPortKey)
        if savedPort > 0 {
            listenPort = savedPort
        }
    }

    func persistListenSettings() {
        UserDefaults.standard.set(listenHost, forKey: Self.listenHostKey)
        UserDefaults.standard.set(listenPort, forKey: Self.listenPortKey)
    }

    private func migrateListenHostForDeviceAccessIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: Self.listenHostDeviceMigrationKey) else { return }
        if listenHost == "127.0.0.1" {
            listenHost = HTTPProxyConfiguration.default.listenHost
        }
        UserDefaults.standard.set(true, forKey: Self.listenHostDeviceMigrationKey)
        persistListenSettings()
    }

    var acceptsRemoteDeviceConnections: Bool {
        HTTPProxyConfiguration.acceptsRemoteDevices(listenHost: listenHost)
    }

    var listenDisplayAddress: String {
        acceptsRemoteDeviceConnections ? "all interfaces" : listenHost
    }

    var macProxyEndpoint: String {
        "\(HTTPProxyConfiguration.systemProxyHost):\(listenPort)"
    }

    /// Loads MITM material when capture starts. Never prompts for admin on launch — only when you explicitly install/trust the root CA.
    func prepareCaptureEnvironment() async {
        tls.refreshInstallationState()
        ensureCertificateIssuerLoaded()
        do {
            let root = try await CertificateManager.shared.ensureRootCA()
            certIssuer.installRoot(root)
            syncSSLMailboxes()
        } catch {
            lastError = error.localizedDescription
            syncSSLMailboxes()
        }
    }

    /// Keeps the in-memory leaf issuer in sync with the persisted root CA (required for HTTPS decryption).
    func ensureCertificateIssuerLoaded() {
        if let root = try? CertificateAuthority.loadPersistedRoot() {
            certIssuer.installRoot(root)
        }
    }

    func syncMapLocalMailbox() {
        rulesMailbox.replace(sessions.mapLocalRules.map(\.snapshot))
    }

    func syncMapRemoteMailbox() {
        mapRemoteMailbox.replace(sessions.mapRemoteRules.map(\.snapshot))
    }

    func syncMappingMailboxes() {
        syncMapLocalMailbox()
        syncMapRemoteMailbox()
        sessions.persistMappingRules()
    }

    func syncSSLMailboxes() {
        sslMailbox.replace(tls.effectiveSSLSettings)
        tls.persistSettings()
        certMailbox.setProvider { [certIssuer] host in
            try certIssuer.leafMaterial(for: host)
        }
    }

    func addDecryptHost(_ host: String) {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return }
        let alreadyListed = tls.sslSettings.includedHosts.contains {
            $0.caseInsensitiveCompare(trimmed) == .orderedSame
        }
        if !alreadyListed {
            tls.sslSettings.includedHosts.append(trimmed)
        }
        tls.sslSettings.interceptAllHosts = false
        tls.sslProxyingEnabled = true
        tls.sslSettings.isEnabled = true
        tls.persistSettings()
        syncSSLMailboxes()
    }

    func removeDecryptHost(_ host: String) {
        tls.sslSettings.includedHosts.removeAll {
            $0.caseInsensitiveCompare(host) == .orderedSame
        }
        tls.persistSettings()
        syncSSLMailboxes()
    }

    func isDecryptEnabled(for host: String) -> Bool {
        if tls.sslSettings.interceptAllHosts {
            return !tls.sslSettings.excludedHosts.contains {
                host.lowercased() == $0.lowercased() || host.lowercased().hasSuffix(".\($0.lowercased())")
            }
        }
        return tls.sslSettings.includedHosts.contains {
            host.lowercased() == $0.lowercased() || host.lowercased().hasSuffix(".\($0.lowercased())")
        }
    }

    func addDecryptHostFromSelection() {
        if let domain = selectedDomainFilter, !domain.isEmpty {
            addDecryptHost(domain)
            return
        }
        if let session = sessions.session(id: sessions.selectedSessionId) {
            addDecryptHost(session.host)
        }
    }

    func syncFeatureMailboxes() {
        var block = features.blockList.snapshot
        block.isEnabled = features.blockListEnabled
        blockListMailbox.replace(block)

        rewriteMailbox.replace(rules: features.rewrite.rules, enabled: features.rewriteEnabled)

        var throttle = features.throttling.snapshot
        if !features.throttlingEnabled {
            throttle = .off
        }
        throttleMailbox.replace(throttle)

        breakpointMailbox.replace(features.breakpoints.settings)
    }

    private func makeProxyCallbacks(store: SessionStore) -> ProxyRuntimeCallbacks {
        let mailbox = rulesMailbox
        let remoteMailbox = mapRemoteMailbox
        let sslBox = sslMailbox
        let certBox = certMailbox
        let blockBox = blockListMailbox
        let rewriteBox = rewriteMailbox
        let throttleBox = throttleMailbox
        let bpBox = breakpointMailbox
        let breakpoints = features.breakpoints
        let remoteTracker = remoteClients

        return ProxyRuntimeCallbacks(
            onHTTPExchange: { snap in
                Task { @MainActor in store.ingest(snap) }
            },
            onCONNECT: { authority, ok, err, clientApp, clientIP, requestHeaders in
                Task { @MainActor in
                    store.ingestCONNECT(
                        authority: authority,
                        connected: ok,
                        error: err,
                        clientAppName: clientApp,
                        clientIPAddress: clientIP,
                        requestHeaders: requestHeaders
                    )
                }
            },
            onRemoteClientConnected: { ip in
                Task { @MainActor in self.registerRemoteClient(ip, connected: true) }
            },
            onRemoteClientDisconnected: { ip in
                Task { @MainActor in self.registerRemoteClient(ip, connected: false) }
            },
            mapLocalRules: { mailbox.current() },
            mapRemoteRules: { remoteMailbox.current() },
            sslSettings: { sslBox.current() },
            leafCertificate: { host in try certBox.leafMaterial(for: host) },
            blockListSettings: { blockBox.current() },
            rewriteRules: { rewriteBox.currentRules() },
            rewriteEnabled: { rewriteBox.isEnabled() },
            throttleSettings: { throttleBox.current() },
            shouldBreakRequest: { url in bpBox.shouldBreak(phase: .request, url: url) },
            shouldBreakResponse: { url in bpBox.shouldBreak(phase: .response, url: url) },
            awaitBreakpoint: { pending in
                bpBox.awaitDecision(pending: pending) { item in
                    Task { @MainActor in breakpoints.queue(item) }
                }
            }
        )
    }

    func toggleProxy() async {
        if isRunning { await stopProxy() } else { await startProxy() }
    }

    func startProxy() async {
        lastError = nil
        captureWarning = nil
        resetCaptureFiltersForStart()
        ensureRemoteCaptureReady()
        await prepareCaptureEnvironment()
        syncMappingMailboxes()
        applyCaptureDefaults()
        syncSSLMailboxes()
        syncFeatureMailboxes()
        let store = sessions
        let callbacks = makeProxyCallbacks(store: store)
        persistListenSettings()
        let config = HTTPProxyConfiguration(listenHost: listenHost, listenPort: listenPort)
        do {
            try await proxyEngine.start(configuration: config, callbacks: callbacks)
            markCaptureSessionActive(true)
            if enableSystemProxy {
                await configureSystemProxyRouting()
            } else {
                refreshSystemProxyRoutingState()
                if systemProxyActive {
                    // Proxy was already configured manually.
                }
            }
            isRunning = true
            refreshCaptureWarnings()
        } catch {
            lastError = error.localizedDescription
            isRunning = false
        }
    }

    /// Routes macOS HTTP/HTTPS traffic through this listener. Skips admin if already configured.
    func configureSystemProxyRouting() async {
        let listenerUp = await proxyEngine.isRunning
        guard isRunning || listenerUp else { return }

        let proxyHost = HTTPProxyConfiguration.systemProxyHost
        let port = listenPort
        let shouldEnable = enableSystemProxy
        let running = isRunning || listenerUp

        let outcome = await Task.detached(priority: .userInitiated) {
            Self.systemProxyRoutingOutcome(
                proxyHost: proxyHost,
                port: port,
                shouldEnable: shouldEnable,
                isRunning: running
            )
        }.value

        applySystemProxyRoutingOutcome(outcome)
    }

    private struct SystemProxyRoutingOutcome: Sendable {
        var active: Bool
        var captureWarning: String?
    }

    private nonisolated static func systemProxyRoutingOutcome(
        proxyHost: String,
        port: Int,
        shouldEnable: Bool,
        isRunning: Bool
    ) -> SystemProxyRoutingOutcome {
        guard isRunning else {
            return SystemProxyRoutingOutcome(active: false, captureWarning: nil)
        }
        guard shouldEnable else {
            let active = SystemProxyManager.verifySystemProxy(host: proxyHost, port: port).isCorrect
            return SystemProxyRoutingOutcome(active: active, captureWarning: nil)
        }

        let verification = SystemProxyManager.verifySystemProxy(host: proxyHost, port: port)
        if verification.isCorrect {
            return SystemProxyRoutingOutcome(active: true, captureWarning: nil)
        }

        do {
            try SystemProxyManager.enable(host: proxyHost, port: port)
            let postEnable = SystemProxyManager.verifySystemProxy(host: proxyHost, port: port)
            if postEnable.isCorrect {
                return SystemProxyRoutingOutcome(active: true, captureWarning: nil)
            }
            return SystemProxyRoutingOutcome(
                active: false,
                captureWarning: SystemProxyManager.SystemProxyError.verificationFailed(postEnable).errorDescription
            )
        } catch let error as SystemProxyManager.SystemProxyError {
            switch error {
            case .authorizationCancelled:
                return SystemProxyRoutingOutcome(active: false, captureWarning: error.errorDescription)
            case .verificationFailed(let result):
                return SystemProxyRoutingOutcome(active: false, captureWarning: SystemProxyManager.SystemProxyError.verificationFailed(result).errorDescription)
            default:
                return SystemProxyRoutingOutcome(
                    active: false,
                    captureWarning: """
                    Proxy is listening, but macOS system proxy could not be enabled: \(error.localizedDescription) \
                    You can still capture traffic by pointing your browser to \(proxyHost):\(port), \
                    or disable “Route macOS traffic” in Proxy settings.
                    """
                )
            }
        } catch let error as SystemCommandRunner.CommandError {
            return SystemProxyRoutingOutcome(active: false, captureWarning: error.errorDescription)
        } catch {
            return SystemProxyRoutingOutcome(
                active: false,
                captureWarning: """
                Proxy is listening, but macOS system proxy could not be enabled: \(error.localizedDescription) \
                You can still capture traffic by pointing your browser to \(proxyHost):\(port), \
                or disable “Route macOS traffic” in Proxy settings.
                """
            )
        }
    }

    private func applySystemProxyRoutingOutcome(_ outcome: SystemProxyRoutingOutcome) {
        systemProxyActive = outcome.active
        if outcome.active {
            systemProxyRestoredThisSession = false
            if captureWarning?.contains("Traffic is not routed") == true
                || captureWarning?.contains("system proxy") == true
                || captureWarning?.contains("Wi‑Fi/Ethernet proxy") == true {
                captureWarning = nil
            }
        } else if let warning = outcome.captureWarning {
            captureWarning = warning
        }
        refreshCaptureWarnings()
    }

    func refreshCaptureWarnings() {
        if isRunning, let deviceHint = captureHealth.deviceConnectionHint {
            captureWarning = deviceHint
            return
        }
        if isRunning, let routing = captureHealth.routingHint {
            captureWarning = routing
            return
        }
        if isRunning,
           acceptsRemoteDeviceConnections,
           deviceProxyAddresses.isEmpty {
            captureWarning =
                "Proxy accepts devices, but no LAN IP was found. Connect your Mac to Wi‑Fi, then set iPhone proxy to your Mac’s IP address."
            return
        }
        if isRunning,
           acceptsRemoteDeviceConnections,
           remoteDeviceIPs.isEmpty,
           !hasRemoteDeviceTraffic {
            captureWarning = deviceProxySetupHint + " Then open Safari on the phone. Mac traffic uses 127.0.0.1 — phones must use your Mac’s LAN IP."
            return
        }
        if isRunning,
           acceptsRemoteDeviceConnections,
           !remoteDeviceIPs.isEmpty,
           !hasRemoteDeviceTraffic {
            let ips = remoteDeviceIPs.joined(separator: ", ")
            captureWarning =
                """
                Mobile device connected (\(ips)) but no API traffic yet. On iPhone: Settings → General → About → \
                Certificate Trust Settings → enable full trust for ShubhranshProxy Root CA. Test Safari first — pinned native apps may not work.
                """
            return
        }
        captureWarning = nil
    }

    /// Whether macOS Wi‑Fi/Ethernet is routed through this listener (cached — never runs shell commands during SwiftUI layout).
    var macSystemProxyIsConfigured: Bool {
        !enableSystemProxy || systemProxyActive
    }

    private func refreshSystemProxyRoutingState() {
        let verification = SystemProxyManager.verifySystemProxy(
            host: HTTPProxyConfiguration.systemProxyHost,
            port: listenPort
        )
        systemProxyActive = verification.isCorrect
    }

    func openMacNetworkProxySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Network-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    var captureHealth: CaptureHealth {
        CaptureHealthEvaluator.evaluate(
            isRunning: isRunning,
            listenHost: listenHost,
            listenPort: listenPort,
            systemProxyActive: systemProxyActive,
            enableSystemProxy: enableSystemProxy,
            rootInstalled: tls.rootCertificateInstalled,
            rootTrusted: tls.rootCertificateTrusted,
            sslEnabled: tls.sslProxyingEnabled && tls.sslSettings.isEnabled,
            isRecording: sessions.isRecording
        )
    }

    func stopProxy() async {
        if restoreSystemProxyOnStop {
            _ = restoreMacOSNetworkProxyIfApplied()
        }
        await proxyEngine.stop()
        isRunning = false
        markCaptureSessionActive(false)
        remoteClients.reset()
        remoteDeviceIPs = []
    }

    func registerRemoteClient(_ ip: String, connected: Bool) {
        guard let normalized = ClientAddressResolver.normalize(ip),
              !ClientAddressResolver.isLoopback(normalized) else { return }
        if connected {
            remoteClients.noteConnection(from: normalized)
            let recentlyLogged = sessions.sessions.contains {
                $0.method == "DEVICE"
                    && ClientAddressResolver.normalize($0.clientIPAddress) == normalized
                    && Date().timeIntervalSince1970 - $0.startedAt < 60
            }
            if !recentlyLogged {
                sessions.ingest(ExchangeSnapshotFactory.devicePresence(clientIPAddress: normalized))
            }
        } else {
            remoteClients.noteDisconnection(from: normalized)
        }
        remoteDeviceIPs = remoteClients.connectedIPs
        invalidateTrafficCatalogCache()
        refreshCaptureWarnings()
    }

    func pinDomain(_ raw: String) {
        let host = FavoritesStore.normalizedHost(from: raw)
        guard !host.isEmpty else { return }
        features.favorites.pin(host)
        invalidateTrafficCatalogCache()
    }

    func unpinDomain(_ host: String) {
        features.favorites.unpin(host)
        invalidateTrafficCatalogCache()
    }

    func pinEndpointURL(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        features.favorites.pinEndpoint(trimmed)
        if let host = URL(string: trimmed)?.host ?? URL(string: "https://\(trimmed)")?.host {
            features.favorites.pin(host)
        }
        notifyFavoritesChanged()
    }

    func notifyFavoritesChanged() {
        invalidateTrafficCatalogCache()
    }

    private func invalidateTrafficCatalogCache() {
        catalogSessionCount = -1
        trafficCatalogRevision += 1
    }

    private func refreshTrafficCatalogIfNeeded() {
        let sessionCount = sessions.sessions.count
        let remoteSignature = remoteDeviceIPs.joined(separator: ",")
        let favoriteSignature = features.favorites.sortedFavorites.joined(separator: ",")
        if sessionCount == catalogSessionCount,
           remoteSignature == catalogRemoteIPSignature,
           favoriteSignature == catalogFavoriteSignature,
           !cachedTrafficDeviceGroups.isEmpty || sessionCount == 0 {
            return
        }

        catalogSessionCount = sessionCount
        catalogRemoteIPSignature = remoteSignature
        catalogFavoriteSignature = favoriteSignature

        cachedTrafficDeviceGroups = TrafficDeviceCatalog.buildDeviceGroups(
            from: sessions.sessions,
            connectedRemoteIPs: remoteDeviceIPs
        )
        cachedApiBaseGroups = APITrafficCatalog.buildBaseGroups(from: sessions.sessions)
        cachedSidebarPinnedGroups = APITrafficCatalog.buildSidebarPinnedGroups(
            pinnedHosts: features.favorites.sortedFavorites,
            pinnedEndpointURLs: Array(features.favorites.favoriteEndpoints),
            sessionGroups: cachedApiBaseGroups
        )
    }

    /// True when any non-Mac session exists from a connected phone (API, CONNECT, or TLS errors).
    var hasRemoteDeviceTraffic: Bool {
        sessions.sessions.contains { session in
            guard session.method != "DEVICE" else { return false }
            guard TrafficDeviceCatalog.deviceKey(for: session) != TrafficDeviceCatalog.macDeviceKey else { return false }
            guard let ip = ClientAddressResolver.normalize(session.clientIPAddress) else { return false }
            return remoteDeviceIPs.contains(ip)
        }
    }

    private func ensureRemoteCaptureReady() {
        if !acceptsRemoteDeviceConnections {
            listenHost = HTTPProxyConfiguration.default.listenHost
        }
        tls.sslSettings.interceptRemoteDevices = true
        if tls.rootCertificateInstalled, tls.rootCertificateTrusted {
            tls.sslProxyingEnabled = true
            tls.sslSettings.isEnabled = true
        }
        tls.persistSettings()
        persistListenSettings()
        syncSSLMailboxes()
    }

    var lanInterfaceAddresses: [NetworkAddressHelper.InterfaceAddress] {
        NetworkAddressHelper.allIPv4Addresses()
    }

    var deviceProxyAddresses: [String] {
        lanInterfaceAddresses.map(\.address)
    }

    func restoreSystemProxyIfNeeded() {
        guard restoreSystemProxyOnQuit else { return }
        _ = restoreMacOSNetworkProxyIfApplied()
    }

    /// Clears in-memory capture data when the app exits (not persisted across launches).
    func clearEphemeralCaptureData() {
        sessions.clearAll()
        invalidateTrafficCatalogCache()
        remoteClients.reset()
        remoteDeviceIPs = []
    }

    /// Synchronous cleanup when the app is quitting — restores macOS network proxy and stops capture.
    private(set) var quitCleanupFinished = false

    /// True when the user should confirm quit so capture and macOS proxy are cleaned up first.
    var needsQuitConfirmation: Bool {
        isRunning || systemProxyActive || SystemProxyManager.hasPersistedRestoreSnapshots()
    }

    /// Stops capture, restores macOS proxy if needed, then allows the app to exit.
    func prepareForApplicationQuit() async {
        guard !quitCleanupFinished else { return }

        if !systemProxyRestoredThisSession {
            let proxyStillActive = SystemProxyManager.isRoutingThroughApp(
                host: HTTPProxyConfiguration.systemProxyHost,
                port: listenPort
            )
            let hasSnapshots = SystemProxyManager.hasPersistedRestoreSnapshots()
            let shouldRestore = isRunning
                ? (restoreSystemProxyOnStop || restoreSystemProxyOnQuit)
                : (restoreSystemProxyOnQuit && (proxyStillActive || hasSnapshots || systemProxyActive))
            if shouldRestore {
                _ = restoreMacOSNetworkProxyIfApplied()
            }
        }

        if isRunning {
            await proxyEngine.stop()
            isRunning = false
            systemProxyActive = false
            markCaptureSessionActive(false)
            remoteClients.reset()
            remoteDeviceIPs = []
        }

        clearEphemeralCaptureData()
        quitCleanupFinished = true
    }

    func performTerminationCleanup() {
        guard !quitCleanupFinished else { return }

        if !systemProxyRestoredThisSession {
            let proxyStillActive = SystemProxyManager.isRoutingThroughApp(
                host: HTTPProxyConfiguration.systemProxyHost,
                port: listenPort
            )
            let hasSnapshots = SystemProxyManager.hasPersistedRestoreSnapshots()
            let shouldRestore = isRunning
                ? (restoreSystemProxyOnStop || restoreSystemProxyOnQuit)
                : (restoreSystemProxyOnQuit && (proxyStillActive || hasSnapshots || systemProxyActive))
            if shouldRestore {
                _ = restoreMacOSNetworkProxyIfApplied()
            }
        }

        if isRunning {
            let group = DispatchGroup()
            group.enter()
            Task {
                await proxyEngine.stop()
                isRunning = false
                systemProxyActive = false
                markCaptureSessionActive(false)
                group.leave()
            }
            _ = group.wait(timeout: .now() + 5)
        }

        clearEphemeralCaptureData()
        quitCleanupFinished = true
    }

    @discardableResult
    private func restoreMacOSNetworkProxyIfApplied() -> Bool {
        if systemProxyRestoredThisSession,
           !SystemProxyManager.isRoutingThroughApp(host: HTTPProxyConfiguration.systemProxyHost, port: listenPort),
           !SystemProxyManager.hasPersistedRestoreSnapshots() {
            systemProxyActive = false
            return true
        }

        let proxyHost = HTTPProxyConfiguration.systemProxyHost
        let configuredOurs = SystemProxyManager.isRoutingThroughApp(host: proxyHost, port: listenPort)
        let hasSnapshots = SystemProxyManager.hasPersistedRestoreSnapshots()
        guard configuredOurs || hasSnapshots || systemProxyActive else { return true }

        do {
            try SystemProxyManager.disable(
                restore: true,
                fallbackHost: proxyHost,
                fallbackPort: listenPort
            )
            systemProxyActive = false
            systemProxyRestoredThisSession = true
            return true
        } catch {
            return false
        }
    }

    private func applyCaptureDefaults() {
        tls.refreshInstallationState()
        if tls.rootCertificateInstalled, tls.rootCertificateTrusted {
            tls.sslProxyingEnabled = true
            tls.sslSettings.isEnabled = true
            syncSSLMailboxes()
        }
    }

    func setEnableSystemProxy(_ enabled: Bool) {
        enableSystemProxy = enabled
        UserDefaults.standard.set(enabled, forKey: "ShubhranshProxy.enableSystemProxy")
    }

    func setRestoreSystemProxyOnStop(_ enabled: Bool) {
        restoreSystemProxyOnStop = enabled
        UserDefaults.standard.set(enabled, forKey: "ShubhranshProxy.restoreSystemProxyOnStop")
    }

    func setRestoreSystemProxyOnQuit(_ enabled: Bool) {
        restoreSystemProxyOnQuit = enabled
        UserDefaults.standard.set(enabled, forKey: "ShubhranshProxy.restoreSystemProxyOnQuit")
    }

    func setRestoreSystemProxyOnExit(_ enabled: Bool) {
        restoreSystemProxyOnStop = enabled
        restoreSystemProxyOnQuit = enabled
        UserDefaults.standard.set(enabled, forKey: "ShubhranshProxy.restoreSystemProxyOnStop")
        UserDefaults.standard.set(enabled, forKey: "ShubhranshProxy.restoreSystemProxyOnQuit")
    }

    var restoreSystemProxyOnExit: Bool {
        restoreSystemProxyOnStop && restoreSystemProxyOnQuit
    }

    func clearSessions() {
        sessions.clearAll()
    }

    func installRootCertificate() async {
        lastError = nil
        do {
            try await tls.ensureRootCertificateReady()
            let root = try await CertificateManager.shared.ensureRootCA()
            certIssuer.installRoot(root)
            syncSSLMailboxes()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func exportRootCertificate(format: RootCertificateExportFormat = .cer) async {
        do {
            let url = try await tls.exportRootCertificateURL(format: format)
            ExportHelpers.saveCertificate(from: url, defaultName: "ShubhranshProxy-Root-CA.\(format.fileExtension)")
        } catch {
            lastError = error.localizedDescription
        }
    }

    func shareRootCertificateViaAirDrop() async {
        lastError = nil
        do {
            let url = try await tls.exportRootCertificateURL(format: .cer)
            if let message = ExportHelpers.shareViaAirDrop(fileURL: url) {
                lastError = message
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    var deviceProxyHost: String {
        if let lan = NetworkAddressHelper.primaryIPv4Address() {
            return lan
        }
        if acceptsRemoteDeviceConnections {
            return deviceProxyAddresses.first ?? "your Mac Wi‑Fi IP"
        }
        return listenHost
    }

    var deviceProxySetupHint: String {
        let addresses = deviceProxyAddresses
        guard !addresses.isEmpty else {
            return "Connect your Mac to Wi‑Fi, then set iPhone proxy to your Mac’s IP address."
        }
        if addresses.count == 1 {
            return "Set iPhone Wi‑Fi proxy to \(addresses[0]):\(listenPort)"
        }
        let listed = addresses.map { "\($0):\(listenPort)" }.joined(separator: " or ")
        return "Set iPhone Wi‑Fi proxy to \(listed) — use the IP on the same network as your phone."
    }

    var deviceProxyEndpoint: String {
        "\(deviceProxyHost):\(listenPort)"
    }

    func revealRootCertificateInFinder() async {
        do {
            let root = try await CertificateManager.shared.ensureRootCA()
            try CertificateAuthority.persistRoot(root)
            let pemURL = try CertificateAuthority.rootPEMFileURL()
            NSWorkspace.shared.activateFileViewerSelecting([pemURL])
        } catch {
            lastError = error.localizedDescription
        }
    }

    func removeRootCertificate() async {
        do {
            try await tls.removeRootCertificate()
            certIssuer.clear()
            syncSSLMailboxes()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func exportSession() {
        do {
            let data = try sessions.exportJSON()
            ExportHelpers.saveJSON(data, defaultName: "ShubhranshProxy-session.json")
        } catch {
            lastError = error.localizedDescription
        }
    }

    func importSession(replace: Bool) {
        ExportHelpers.pickJSON { data in
            guard let data else { return }
            Task { @MainActor in
                do {
                    try self.sessions.importJSON(data, merge: !replace)
                } catch {
                    self.lastError = error.localizedDescription
                }
            }
        }
    }

    func exportHAR() {
        do {
            let data = try HARExporter.exportHAR(sessions: sessions.sessions)
            ExportHelpers.saveHAR(data, defaultName: "ShubhranshProxy.har")
        } catch {
            lastError = error.localizedDescription
        }
    }

    func importHAR(replace: Bool) {
        ExportHelpers.pickHAR { data in
            guard let data else { return }
            Task { @MainActor in
                do {
                    let loaded = try HARImporter.importSessions(from: data)
                    self.sessions.importSessions(loaded, merge: !replace)
                } catch {
                    self.lastError = error.localizedDescription
                }
            }
        }
    }

    var statusLine: String {
        if let lastError { return "Error: \(lastError)" }
        if isRunning { return compactCaptureStatus }
        return "Stopped"
    }

    /// Single-line status for toolbars and title bars — avoids pushing controls off-screen.
    var compactCaptureStatus: String {
        guard isRunning else { return "Stopped" }
        var parts: [String] = []
        parts.append("Listening :\(listenPort)")
        if !remoteDeviceIPs.isEmpty {
            parts.append("\(remoteDeviceIPs.count) mobile connected")
        } else if acceptsRemoteDeviceConnections, let ip = deviceProxyAddresses.first {
            parts.append("phone → \(ip):\(listenPort)")
        }
        if systemProxyActive {
            parts.append("Mac routed")
        }
        if tls.sslProxyingEnabled {
            parts.append(tls.rootCertificateTrusted ? "SSL on" : "SSL needs trust")
        }
        return parts.joined(separator: " · ")
    }

    var detailedCaptureStatus: String {
        if let lastError { return "Error: \(lastError)" }
        if !isRunning { return "Stopped — press Start to capture traffic." }
        var lines: [String] = []
        lines.append("Listening on \(listenDisplayAddress):\(listenPort)")
        if acceptsRemoteDeviceConnections {
            if deviceProxyAddresses.count <= 1 {
                lines.append("iPhone/Android → \(deviceProxyEndpoint)")
            } else {
                lines.append("iPhone/Android → \(deviceProxyAddresses.map { "\($0):\(listenPort)" }.joined(separator: " or "))")
            }
            if !remoteDeviceIPs.isEmpty {
                lines.append("\(remoteDeviceIPs.count) mobile device\(remoteDeviceIPs.count == 1 ? "" : "s") connected")
            }
        }
        if let warning = captureWarning {
            lines.append(warning)
        }
        return lines.joined(separator: "\n")
    }

    var sessionsForTable: [ProxySession] {
        var list = sessions.filteredSessions
        if showFavoritesOnly {
            list = list.filter {
                features.favorites.isFavoriteEndpoint($0.url) || features.favorites.isFavorite($0.host)
            }
        }
        if let device = selectedDeviceFilter, !device.isEmpty {
            list = list.filter { TrafficDeviceCatalog.deviceKey(for: $0) == device }
        }
        if let domain = selectedDomainFilter, !domain.isEmpty {
            list = list.filter { $0.host.caseInsensitiveCompare(domain) == .orderedSame }
        }
        if let base = selectedBaseURLFilter, !base.isEmpty {
            list = list.filter { APITrafficCatalog.baseURL(from: $0.url) == base }
        }
        if let endpoint = selectedEndpointKey, !endpoint.isEmpty {
            list = list.filter {
                APITrafficCatalog.endpointKey(
                    method: $0.method,
                    url: $0.url,
                    host: $0.host,
                    isCONNECT: $0.isCONNECT
                ) == endpoint
            }
        }
        if let url = selectedURLFilter, !url.isEmpty {
            list = list.filter { SessionDisplayRules.normalizedURLKey($0.url) == url }
        }
        list = list.filter { sessionContentFilter.matches($0) }
        list = list.filter { $0.method != "DEVICE" }
        return list
    }

    var trafficDeviceGroups: [TrafficDeviceGroup] {
        refreshTrafficCatalogIfNeeded()
        return cachedTrafficDeviceGroups
    }

    var apiBaseGroups: [APIBaseGroup] {
        refreshTrafficCatalogIfNeeded()
        return cachedApiBaseGroups
    }

    var sidebarPinnedGroups: [APIBaseGroup] {
        refreshTrafficCatalogIfNeeded()
        return cachedSidebarPinnedGroups
    }

    var favoriteAPIGroups: [APIBaseGroup] {
        sidebarPinnedGroups
    }

    func selectDevice(_ deviceKey: String) {
        selectedDeviceFilter = deviceKey
        selectedDomainFilter = nil
        selectedBaseURLFilter = nil
        selectedEndpointKey = nil
        selectedURLFilter = nil
        if activeCaptureView != .favorites {
            activeCaptureView = .sessions
        }
    }

    func selectDomain(_ host: String, deviceKey: String? = nil) {
        selectedDeviceFilter = deviceKey
        selectedDomainFilter = host
        selectedBaseURLFilter = nil
        selectedEndpointKey = nil
        selectedURLFilter = nil
        if activeCaptureView != .favorites {
            activeCaptureView = .sessions
        }
    }

    func selectEndpoint(_ endpoint: APIEndpointSummary) {
        selectedEndpointKey = endpoint.endpointKey
        selectedBaseURLFilter = nil
        selectedDomainFilter = endpoint.host
        selectedURLFilter = nil
        if activeCaptureView != .favorites {
            activeCaptureView = .sessions
        }
    }

    func selectBaseURL(_ baseURL: String, host: String) {
        selectDomain(host)
    }

    func clearTrafficFilters() {
        selectedDeviceFilter = nil
        selectedDomainFilter = nil
        selectedBaseURLFilter = nil
        selectedEndpointKey = nil
        selectedURLFilter = nil
        sessionContentFilter = .all
        sessions.searchText = ""
        sessions.filterMethod = ""
        sessions.filterStatusCode = ""
        if activeCaptureView == .favorites {
            activeCaptureView = .sessions
        }
    }

    /// Clears sidebar/table filters when capture starts so traffic is not hidden by a stale pin/filter.
    func resetCaptureFiltersForStart() {
        selectedDeviceFilter = nil
        selectedDomainFilter = nil
        selectedBaseURLFilter = nil
        selectedEndpointKey = nil
        selectedURLFilter = nil
        sessionContentFilter = .all
        sessions.searchText = ""
        sessions.filterMethod = ""
        sessions.filterStatusCode = ""
        if activeCaptureView == .favorites {
            activeCaptureView = .sessions
        }
        if !sessions.isRecording {
            sessions.isRecording = true
        }
    }

    var hiddenSessionCount: Int {
        max(0, sessions.filteredSessions.count - sessionsForTable.count)
    }

    var rawVisibleSessionCount: Int {
        sessions.sessions.filter(SessionDisplayRules.shouldCapture).count
    }

    /// Clears sidebar filters but keeps the Favorites tab active.
    func prepareFavoritesView() {
        selectedDeviceFilter = nil
        selectedDomainFilter = nil
        selectedBaseURLFilter = nil
        selectedEndpointKey = nil
        selectedURLFilter = nil
        activeCaptureView = .favorites
    }

    var favoritesSessionCount: Int {
        sessions.filteredSessions.filter {
            features.favorites.isFavoriteEndpoint($0.url) || features.favorites.isFavorite($0.host)
        }.count
    }

    var hasActiveTrafficFilter: Bool {
        selectedDeviceFilter != nil
            || selectedDomainFilter != nil
            || selectedBaseURLFilter != nil
            || selectedEndpointKey != nil
            || selectedURLFilter != nil
            || showFavoritesOnly
    }

    func presentMappingTools(prefill: MappingToolsPrefill? = nil) {
        if let prefill {
            mappingToolsPrefill = prefill
        }
        showMappingToolsSheet = true
    }

    func presentAllMappedURLs() {
        presentMappingTools(prefill: MappingToolsPrefill(mode: .allMapped, matchURL: ""))
    }

    var mappedRuleCount: Int {
        sessions.mapLocalRules.count + sessions.mapRemoteRules.count
    }

    var enabledMappedRuleCount: Int {
        sessions.mapLocalRules.filter(\.isEnabled).count + sessions.mapRemoteRules.filter(\.isEnabled).count
    }

    func consumeMappingToolsPrefill() -> MappingToolsPrefill? {
        defer { mappingToolsPrefill = nil }
        return mappingToolsPrefill
    }

    func dismissMappingTools() {
        returnToCaptureHome()
    }

    /// Returns to the main capture screen from tools, map editors, or SSL.
    func returnToCaptureHome() {
        activeCaptureView = .sessions
        showMappingToolsSheet = false
    }
}

enum SessionContentFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case http = "HTTP"
    case https = "HTTPS"
    case json = "JSON"
    case other = "Other"

    var id: String { rawValue }
    var label: String { rawValue }

    func matches(_ session: ProxySession) -> Bool {
        switch self {
        case .all:
            return true
        case .http:
            return session.url.lowercased().hasPrefix("http://")
        case .https:
            return session.url.lowercased().hasPrefix("https://") || session.wasDecryptedHTTPS
        case .json:
            if let mime = session.mimeType?.lowercased(), mime.contains("json") { return true }
            if let body = session.responseBody, BodyFormatting.looksLikeJSON(body) { return true }
            return false
        case .other:
            if let mime = session.mimeType?.lowercased() {
                return !mime.contains("json") && !mime.contains("html") && !mime.contains("text")
            }
            return true
        }
    }
}

enum CaptureView: String, CaseIterable, Identifiable, Hashable {
    case sessions = "Sessions"
    case favorites = "Favorites"
    case ssl = "SSL"
    case tools = "Tools"
    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .sessions: "list.bullet.rectangle"
        case .favorites: "star.fill"
        case .ssl: "lock.shield"
        case .tools: "wrench.and.screwdriver"
        }
    }
}

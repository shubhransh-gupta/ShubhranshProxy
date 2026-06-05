//
//  SetupGuideView.swift
//  ShubhranshProxy
//  Created by Shubhransh Gupta
//

import SwiftUI

private enum SetupPlatform: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case mac = "Mac"
    case ios = "iOS"
    case android = "Android"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .overview: "checklist"
        case .mac: "desktopcomputer"
        case .ios: "iphone"
        case .android: "smartphone"
        }
    }
}

struct SetupGuideView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @State private var platform: SetupPlatform = .overview
    @State private var lanIP = NetworkAddressHelper.primaryIPv4Address() ?? "—"

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                setupHeader
                Divider()
                Picker("Platform", selection: $platform) {
                    ForEach(SetupPlatform.allCases) { item in
                        Label(item.rawValue, systemImage: item.icon).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 10)

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        switch platform {
                        case .overview:
                            overviewSection
                        case .mac:
                            macSection
                        case .ios:
                            iosSection
                        case .android:
                            androidSection
                        }

                        certificateActionsSection
                        troubleshootingSection
                    }
                    .padding()
                }
            }
            .navigationTitle("Setup Guide")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Refresh IP") { refreshLanIP() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                refreshLanIP()
                appState.tls.refreshInstallationState()
            }
        }
    }

    // MARK: - Header

    private var setupHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Capture HTTPS traffic on Mac, iOS, and Android")
                .font(.title3.bold())

            HStack(spacing: 16) {
                statusPill(
                    title: "Proxy",
                    value: appState.deviceProxyEndpoint,
                    ok: appState.isRunning
                )
                statusPill(
                    title: "SSL",
                    value: appState.tls.rootCertificateTrusted ? "Trusted" : "Needs setup",
                    ok: appState.tls.rootCertificateTrusted
                )
                statusPill(
                    title: "LAN IP",
                    value: lanIP,
                    ok: lanIP != "—"
                )
            }

            if !appState.isRunning {
                Text("Start ShubhranshProxy (⌘⇧R) before testing devices on your network.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
    }

    // MARK: - Overview

    private var overviewSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            setupIntro(
                title: "Whole setup in four steps",
                detail: "Complete these once per device. Your Mac runs the proxy; phones must use your Mac’s LAN IP — not 127.0.0.1."
            )

            setupStepCard(
                number: 1,
                title: "Start ShubhranshProxy on your Mac",
                body: "Press Start or ⌘⇧R. Default listen port is \(appState.listenPort). Keep the Mac awake and on the same Wi‑Fi as your phone."
            )
            setupStepCard(
                number: 2,
                title: "Point the device proxy to your Mac",
                body: "On iOS or Android, set manual HTTP/HTTPS proxy to **\(effectiveLanIP)** port **\(appState.listenPort)**. See the iOS or Android tab for exact taps."
            )
            setupStepCard(
                number: 3,
                title: "Install the root CA on the device",
                body: "HTTPS requires trusting ShubhranshProxy’s certificate on each physical device. Use AirDrop on iOS or transfer the .cer file to Android."
            )
            setupStepCard(
                number: 4,
                title: "Capture traffic",
                body: "Browse on the device. Requests appear in ShubhranshProxy when SSL Proxying is enabled and the certificate is trusted."
            )

            HStack(spacing: 12) {
                Button("Mac setup") { platform = .mac }
                Button("iOS setup") { platform = .ios }
                Button("Android setup") { platform = .android }
            }
            .buttonStyle(.link)
        }
    }

    // MARK: - Mac

    private var macSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            setupIntro(
                title: "Mac setup",
                detail: "Capture traffic from this Mac automatically or from individual apps."
            )

            setupStepCard(
                number: 1,
                title: "Start capture",
                body: "Press **Start** or **⌘⇧R**. With **Route macOS traffic (system proxy)** enabled, Safari and most apps use **\(appState.macProxyEndpoint)** automatically."
            )

            GroupBox("Per-app proxy (optional)") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("**Firefox:** Settings → Network → Manual proxy → HTTP & HTTPS → \(appState.macProxyEndpoint)")
                    Text("**Chrome (dev):** quit Chrome, then run:")
                    copyableBlock(chromeCommand)
                    Text("**Terminal:**")
                    copyableBlock(terminalProxyExports)
                }
                .font(.callout)
            }

            setupStepCard(
                number: 2,
                title: "Trust the root CA on this Mac",
                body: "ShubhranshProxy installs its root certificate automatically. If HTTPS still fails, open **SSL Proxy** and click **Reinstall & trust root CA**."
            ) {
                HStack {
                    Button("Install / retry certificate") {
                        Task { await appState.installRootCertificate() }
                    }
                    .disabled(appState.tls.isPreparingCertificate)
                    Text(appState.tls.statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - iOS

    private var iosSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            setupIntro(
                title: "iOS physical device",
                detail: "iPhone and iPad must share Wi‑Fi with this Mac and trust the ShubhranshProxy root CA."
            )

            setupStepCard(
                number: 1,
                title: "Connect to the same Wi‑Fi",
                body: "Your iPhone/iPad and Mac must be on the same network. VPN on the phone can block the proxy."
            )

            setupStepCard(
                number: 2,
                title: "Configure Wi‑Fi proxy",
                body: """
                **Settings → Wi‑Fi → ⓘ next to your network → Configure Proxy → Manual**
                • Server: **\(effectiveLanIP)**
                • Port: **\(appState.listenPort)**
                • Authentication: Off
                """
            ) {
                HStack(spacing: 8) {
                    Button("Copy server IP") { copy(effectiveLanIP) }
                    Button("Copy port") { copy("\(appState.listenPort)") }
                }
                .font(.caption)
            }

            setupStepCard(
                number: 3,
                title: "Install the root certificate",
                body: """
                Send **ShubhranshProxy-Root-CA.cer** to your iPhone:
                1. Tap **AirDrop to iPhone** below (fastest), or save the .cer and AirDrop from Finder.
                2. On iPhone, accept the AirDrop and allow profile download.
                3. **Settings → General → VPN & Device Management** → install the downloaded profile.
                """
            ) {
                iosCertificateButtons
            }

            setupStepCard(
                number: 4,
                title: "Enable full trust for HTTPS",
                body: """
                **Settings → General → About → Certificate Trust Settings**
                Turn on full trust for **ShubhranshProxy Root CA**.
                Without this step, HTTPS sites will fail on the device.
                """
            )

            setupStepCard(
                number: 5,
                title: "Verify capture",
                body: "Start ShubhranshProxy on your Mac, open Safari on the iPhone, and browse any HTTPS site. Sessions should appear in the table."
            )
        }
    }

    // MARK: - Android

    private var androidSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            setupIntro(
                title: "Android physical device",
                detail: "Android requires a manual Wi‑Fi proxy and a user-installed CA certificate for HTTPS decryption."
            )

            setupStepCard(
                number: 1,
                title: "Connect to the same Wi‑Fi",
                body: "Phone and Mac must be on the same LAN. Disable always-on VPN if proxy traffic does not appear."
            )

            setupStepCard(
                number: 2,
                title: "Configure Wi‑Fi proxy",
                body: """
                **Settings → Network & Internet → Internet → Wi‑Fi → your network → Advanced / Proxy → Manual**
                • Proxy host: **\(effectiveLanIP)**
                • Proxy port: **\(appState.listenPort)**
                """
            ) {
                HStack(spacing: 8) {
                    Button("Copy host") { copy(effectiveLanIP) }
                    Button("Copy port") { copy("\(appState.listenPort)") }
                }
                .font(.caption)
            }

            setupStepCard(
                number: 3,
                title: "Transfer the root certificate",
                body: """
                Export **ShubhranshProxy-Root-CA.cer** and move it to the phone (Google Drive, email, USB, or messaging app).
                """
            ) {
                androidCertificateButtons
            }

            setupStepCard(
                number: 4,
                title: "Install as a CA certificate",
                body: """
                **Settings → Security → More security settings → Encryption & credentials → Install a certificate → CA certificate**
                (On some devices: **Settings → Security & privacy → More security & privacy → Install from storage**.)

                Pick **ShubhranshProxy-Root-CA.cer** and confirm installation. Android may require a screen lock PIN first.
                """
            )

            setupStepCard(
                number: 5,
                title: "Verify capture",
                body: "With ShubhranshProxy running on your Mac, open Chrome on Android. HTTP and HTTPS requests should appear in the session list."
            )

            Text("Note: Some Android apps use certificate pinning and will not be intercepted even with the CA installed.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Shared sections

    private var certificateActionsSection: some View {
        GroupBox("Certificate for mobile devices") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Install this root CA on each phone or tablet that should decrypt HTTPS. Your Mac already uses the same certificate.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    Button {
                        Task { await appState.shareRootCertificateViaAirDrop() }
                    } label: {
                        Label("AirDrop to iPhone/iPad", systemImage: "airdrop")
                    }
                    .help("Fastest way to install the certificate on a nearby iOS device")

                    Button("Save .cer file…") {
                        Task { await appState.exportRootCertificate(format: .cer) }
                    }

                    Button("Save .pem file…") {
                        Task { await appState.exportRootCertificate(format: .pem) }
                    }

                    Button("Show in Finder") {
                        Task { await appState.revealRootCertificateInFinder() }
                    }
                }

                if platform == .ios {
                    Text("After AirDrop: install the profile, then enable trust under Certificate Trust Settings (step 4 on the iOS tab).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var troubleshootingSection: some View {
        GroupBox("Troubleshooting") {
            VStack(alignment: .leading, spacing: 8) {
                bullet("If **LAN IP** shows **—**, connect Wi‑Fi or click **Refresh IP**.")
                bullet("In **Proxy settings**, Listen Host must be **0.0.0.0** (all interfaces). Stop capture, change it, then Start again.")
                bullet("Physical devices cannot use **127.0.0.1** — always use your Mac’s LAN address (**\(effectiveLanIP)**).")
                bullet("Allow incoming connections for ShubhranshProxy in **System Settings → Network → Firewall** if devices cannot connect.")
                bullet("When you finish capturing, turn off the iPhone Wi‑Fi proxy (**Settings → Wi‑Fi → ⓘ → Configure Proxy → Off**). ShubhranshProxy restores the Mac proxy automatically on Stop/Quit.")
                bullet("Turn off other proxies (Proxyman, Charles) that may use port 9090.")
                bullet("On iOS, both profile install **and** Certificate Trust Settings are required.")
            }
            .font(.caption)
        }
    }

    @ViewBuilder
    private var iosCertificateButtons: some View {
        HStack(spacing: 10) {
            Button {
                Task { await appState.shareRootCertificateViaAirDrop() }
            } label: {
                Label("AirDrop to iPhone/iPad", systemImage: "airdrop")
            }
            Button("Save .cer…") {
                Task { await appState.exportRootCertificate(format: .cer) }
            }
        }
        .font(.caption)
    }

    @ViewBuilder
    private var androidCertificateButtons: some View {
        HStack(spacing: 10) {
            Button("Save .cer for Android…") {
                Task { await appState.exportRootCertificate(format: .cer) }
            }
            Button("Save .pem…") {
                Task { await appState.exportRootCertificate(format: .pem) }
            }
        }
        .font(.caption)
    }

    // MARK: - Helpers

    private var effectiveLanIP: String {
        lanIP == "—" ? appState.deviceProxyHost : lanIP
    }

    private var chromeCommand: String {
        "open -na \"Google Chrome\" --args --proxy-server=\"http://\(appState.macProxyEndpoint)\""
    }

    private var terminalProxyExports: String {
        """
        export http_proxy=http://\(appState.macProxyEndpoint)
        export https_proxy=http://\(appState.macProxyEndpoint)
        """
    }

    private func refreshLanIP() {
        lanIP = NetworkAddressHelper.primaryIPv4Address() ?? "—"
    }

    private func copy(_ text: String) {
        ExportHelpers.copyToPasteboard(text)
    }

    private func setupIntro(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.title3.bold())
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func setupStepCard(
        number: Int,
        title: String,
        body: String,
        @ViewBuilder actions: () -> some View = { EmptyView() }
    ) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(number)")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Color.accentColor))
                    Text(title)
                        .font(.headline)
                }
                Text(.init(body))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                actions()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func statusPill(title: String, value: String, ok: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Label(value, systemImage: ok ? "checkmark.circle.fill" : "exclamationmark.circle")
                .font(.caption.monospacedDigit())
                .foregroundStyle(ok ? .green : .orange)
                .lineLimit(1)
        }
    }

    private func copyableBlock(_ text: String) -> some View {
        HStack(alignment: .top) {
            Text(text)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Copy") { copy(text) }
                .font(.caption2)
        }
        .padding(8)
        .background(.quaternary.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
            Text(.init(text))
        }
    }
}

//
//  SSLProxySettingsView.swift
//  ShubhranshProxy — UI (Phase 2)
//  Created by Shubhransh Gupta
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SSLProxySettingsView: View {
    @Bindable var appState: AppState
    @State private var newDecryptHost = ""

    var body: some View {
        @Bindable var tls = appState.tls
        Form {
            Section {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(appState.tls.statusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if appState.tls.isPreparingCertificate {
                            ProgressView("Installing root certificate…")
                                .font(.caption)
                        }
                    }
                } icon: {
                    Image(systemName: statusIcon)
                        .foregroundStyle(statusColor)
                }
            }

            Section("Root certificate") {
                Text("The root CA is installed automatically. Mac apps use selective decryption (add hosts below). iPhone/Android HTTPS is decrypted automatically when **Decrypt iPhone/Android traffic** is on.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    statusBadge("Generated", ok: true)
                    statusBadge("Keychain", ok: appState.tls.rootCertificateInstalled)
                    statusBadge("Trusted", ok: appState.tls.rootCertificateTrusted)
                }

                Button("Refresh trust status") {
                    appState.tls.refreshInstallationState()
                    appState.syncSSLMailboxes()
                }

                Button("Reinstall & trust root CA") {
                    Task { await appState.installRootCertificate() }
                }
                .disabled(appState.tls.isPreparingCertificate)

                Menu("Export certificate") {
                    Button("AirDrop to iPhone/iPad…") {
                        Task { await appState.shareRootCertificateViaAirDrop() }
                    }
                    Button("Export .cer file…") {
                        Task { await appState.exportRootCertificate(format: .cer) }
                    }
                    Button("Export .pem file…") {
                        Task { await appState.exportRootCertificate(format: .pem) }
                    }
                    Button("Show certificate in Finder") {
                        Task { await appState.revealRootCertificateInFinder() }
                    }
                }

                if appState.tls.rootCertificateInstalled {
                    Button("Remove from Keychain", role: .destructive) {
                        Task { await appState.removeRootCertificate() }
                    }
                }

                if let trustNote = appState.tls.lastTrustError {
                    Text(trustNote)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Section("HTTPS decryption") {
                Toggle("Enable SSL Proxying", isOn: $tls.sslProxyingEnabled)
                    .disabled(!appState.tls.rootCertificateInstalled)
                    .onChange(of: tls.sslProxyingEnabled) { _, enabled in
                        tls.sslSettings.isEnabled = enabled
                        appState.syncSSLMailboxes()
                    }

                Toggle("Decrypt iPhone/Android traffic", isOn: $tls.sslSettings.interceptRemoteDevices)
                    .onChange(of: tls.sslSettings.interceptRemoteDevices) { _, enabled in
                        if enabled {
                            tls.sslProxyingEnabled = true
                            tls.sslSettings.isEnabled = true
                        }
                        appState.syncSSLMailboxes()
                    }

                Toggle("Decrypt all HTTPS hosts", isOn: $tls.sslSettings.interceptAllHosts)
                    .onChange(of: tls.sslSettings.interceptAllHosts) { _, decryptAll in
                        if decryptAll {
                            tls.sslProxyingEnabled = true
                            tls.sslSettings.isEnabled = true
                        }
                        appState.syncSSLMailboxes()
                    }

                if tls.sslSettings.interceptRemoteDevices && !tls.sslSettings.interceptAllHosts {
                    Text("Traffic from phones/tablets on your Wi‑Fi is decrypted automatically so requests appear in the session list. Mac apps still use the decrypt list below.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if tls.sslSettings.interceptAllHosts {
                    Text("All HTTPS is decrypted except excluded hosts below. This can break Slack, banking apps, and other certificate-pinned services.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else {
                    Text("Only hosts in the decrypt list below are MITM-decrypted. Everything else is tunneled without decryption.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !tls.sslSettings.interceptAllHosts {
                    decryptHostEditor
                }

                TextField("Excluded hosts (comma-separated)", text: excludedBinding)
                    .font(.system(.body, design: .monospaced))
                    .onSubmit { appState.syncSSLMailboxes() }
            }

            Section("Mobile devices (iOS & Android)") {
                Text("Mac traffic uses 127.0.0.1 automatically. Phones must use one of your Mac’s LAN addresses below — never 127.0.0.1.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if appState.lanInterfaceAddresses.isEmpty {
                    Text("No LAN IP detected. Connect your Mac to the same Wi‑Fi as your phone.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else {
                    ForEach(appState.lanInterfaceAddresses) { iface in
                        LabeledContent("\(iface.name)") {
                            Text("\(iface.address):\(appState.listenPort)")
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }
                }

                if !appState.remoteDeviceIPs.isEmpty {
                    LabeledContent("Connected phones") {
                        Text(appState.remoteDeviceIPs.joined(separator: ", "))
                            .font(.system(.body, design: .monospaced))
                    }
                }

                Button("AirDrop certificate to iPhone/iPad…") {
                    Task { await appState.shareRootCertificateViaAirDrop() }
                }

                Button("Save .cer for Android / manual install…") {
                    Task { await appState.exportRootCertificate(format: .cer) }
                }
            }

            Section("Notes") {
                Text("Add only the API domains you need to inspect. After adding a host, make a new request to that domain so the proxy can decrypt it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("SSL Proxy")
        .onAppear {
            appState.tls.refreshInstallationState()
            appState.syncSSLMailboxes()
        }
    }

    private var decryptHostEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                TextField("Host to decrypt (e.g. api.example.com)", text: $newDecryptHost)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                Button("Add") {
                    appState.addDecryptHost(newDecryptHost)
                    newDecryptHost = ""
                }
                .disabled(newDecryptHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            HStack(spacing: 8) {
                Button("Add selected session host") {
                    appState.addDecryptHostFromSelection()
                }
                .disabled(!canAddFromSelection)
                if let domain = appState.selectedDomainFilter {
                    Button("Add filtered domain") {
                        appState.addDecryptHost(domain)
                    }
                }
            }
            .font(.caption)

            if appState.tls.sslSettings.includedHosts.isEmpty {
                Text("No decrypt hosts yet. HTTPS passes through without decryption until you add domains here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(appState.tls.sslSettings.includedHosts, id: \.self) { host in
                    HStack {
                        Image(systemName: "lock.open.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                        Text(host)
                            .font(.system(.callout, design: .monospaced))
                        Spacer()
                        Button("Remove", role: .destructive) {
                            appState.removeDecryptHost(host)
                        }
                        .buttonStyle(.link)
                        .font(.caption)
                    }
                }
            }
        }
    }

    private var canAddFromSelection: Bool {
        appState.sessions.session(id: appState.sessions.selectedSessionId) != nil
            || appState.selectedDomainFilter != nil
    }

    private var statusIcon: String {
        if appState.tls.rootCertificateTrusted && appState.tls.sslProxyingEnabled { return "checkmark.seal.fill" }
        if appState.tls.rootCertificateInstalled { return "lock.shield" }
        return "exclamationmark.triangle.fill"
    }

    private var statusColor: Color {
        if appState.tls.rootCertificateTrusted && appState.tls.sslProxyingEnabled { return .green }
        if appState.tls.rootCertificateInstalled { return .orange }
        return .orange
    }

    private func statusBadge(_ title: String, ok: Bool) -> some View {
        Label(title, systemImage: ok ? "checkmark.circle.fill" : "circle")
            .font(.caption)
            .foregroundStyle(ok ? .green : .secondary)
    }

    private var excludedBinding: Binding<String> {
        Binding(
            get: { appState.tls.sslSettings.excludedHosts.joined(separator: ", ") },
            set: {
                appState.tls.sslSettings.excludedHosts = $0
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            }
        )
    }
}

//
//  CaptureControlStrip.swift
//  ShubhranshProxy
//  Created by Shubhransh Gupta
//
//  Always-visible capture controls — avoids macOS toolbar overflow when device status grows.
//

import AppKit
import SwiftUI

struct CaptureControlStrip: View {
    @Environment(AppState.self) private var appState
    @Binding var showSetup: Bool

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                startStopButton

                Divider().frame(height: 18)

                recordToggle
                sslToggle

                Divider().frame(height: 18)

                Button("Clear", systemImage: "trash") {
                    appState.clearSessions()
                }
                .help("Clear session list (⌘⇧K)")
                .keyboardShortcut("k", modifiers: [.command, .shift])

                Button("Setup", systemImage: "questionmark.circle") {
                    showSetup = true
                }
                .help("Setup guide for Mac + iPhone")

                Button {
                    appState.presentMappingTools()
                } label: {
                    Label("Map", systemImage: "arrow.triangle.swap")
                }
                .help(appState.mappedRuleCount > 0 ? "\(appState.mappedRuleCount) mapped rules" : "Map Local & Map Remote")

                exportMenu
                toolsMenu
            }
            .buttonStyle(.borderless)
            .labelStyle(.titleAndIcon)
            .font(.callout)
            .controlSize(.small)
        }
    }

    private var startStopButton: some View {
        Button {
            Task { await appState.toggleProxy() }
        } label: {
            Label(
                appState.isRunning ? "Stop" : "Start",
                systemImage: appState.isRunning ? "stop.circle.fill" : "play.circle.fill"
            )
        }
        .buttonStyle(.borderedProminent)
        .tint(appState.isRunning ? .red : .accentColor)
        .keyboardShortcut("r", modifiers: [.command, .shift])
        .help(appState.isRunning ? "Stop capture (⌘⇧R)" : "Start capture (⌘⇧R)")
    }

    private var recordToggle: some View {
        Toggle(isOn: Binding(
            get: { appState.sessions.isRecording },
            set: { appState.sessions.isRecording = $0 }
        )) {
            Label("Record", systemImage: "record.circle")
        }
        .toggleStyle(.button)
        .help("Record new sessions to the list")
    }

    private var sslToggle: some View {
        Toggle(isOn: Binding(
            get: { appState.tls.sslProxyingEnabled },
            set: { enabled in
                appState.tls.sslProxyingEnabled = enabled
                appState.tls.sslSettings.isEnabled = enabled
                appState.syncSSLMailboxes()
            }
        )) {
            Label("SSL", systemImage: "lock.shield")
        }
        .toggleStyle(.button)
        .disabled(!appState.tls.rootCertificateInstalled || appState.tls.isPreparingCertificate)
        .help(appState.tls.statusMessage)
    }

    private var exportMenu: some View {
        Menu("Export", systemImage: "square.and.arrow.up") {
            Button("JSON session") { appState.exportSession() }
            Button("HAR file") { appState.exportHAR() }
            Button("Import HAR…") { appState.importHAR(replace: false) }
            Divider()
            Button("Root CA (.cer)…") {
                Task { await appState.exportRootCertificate(format: .cer) }
            }
            Button("Root CA (.pem)…") {
                Task { await appState.exportRootCertificate(format: .pem) }
            }
            if let session = appState.sessions.session(id: appState.sessions.selectedSessionId) {
                Button("Copy as cURL") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(HARExporter.exportCURL(session: session), forType: .string)
                }
            }
        }
    }

    private var toolsMenu: some View {
        Menu("Tools", systemImage: "wrench.and.screwdriver") {
            Button("Map Local & Map Remote…") { appState.presentMappingTools() }
            Button("All Mapped URLs…") { appState.presentAllMappedURLs() }
            Divider()
            Button("Breakpoints…") { appState.activeCaptureView = .tools }
            Button("Rewrite…") { appState.activeCaptureView = .tools }
            Button("Throttling…") { appState.activeCaptureView = .tools }
            Button("Block list…") { appState.activeCaptureView = .tools }
            Button("Composer…") { appState.activeCaptureView = .tools }
            Divider()
            Button("Diff sessions…") { appState.activeCaptureView = .tools }
            Button("Import HAR (replace)…") { appState.importHAR(replace: true) }
        }
    }
}

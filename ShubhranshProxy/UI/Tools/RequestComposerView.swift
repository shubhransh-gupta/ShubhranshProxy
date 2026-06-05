//
//  RequestComposerView.swift — Phase 4
//
//  Created by Shubhransh Gupta

import SwiftUI

struct RequestComposerView: View {
    @Bindable var appState: AppState
    @State private var isSending = false
    @State private var statusMessage: String?

    var body: some View {
        @Bindable var features = appState.features
        @Bindable var composer = features.composer
        Form {
            Section("Request") {
                TextField("Method", text: $composer.method)
                TextField("URL", text: $composer.url)
                    .font(.system(.body, design: .monospaced))
            }
            Section("Headers (one per line)") {
                TextEditor(text: $composer.headers)
                    .font(.system(.caption, design: .monospaced))
                    .frame(minHeight: 100)
            }
            Section("Body") {
                TextEditor(text: $composer.body)
                    .font(.system(.caption, design: .monospaced))
                    .frame(minHeight: 120)
            }
            Section {
                Button(isSending ? "Sending…" : "Send via proxy") {
                    Task { await send() }
                }
                .disabled(isSending || !appState.isRunning)
                if !appState.isRunning {
                    Text("Start the proxy first — Composer routes through \(appState.listenHost):\(appState.listenPort).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let statusMessage {
                    Text(statusMessage).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Composer")
    }

    private func send() async {
        let composer = appState.features.composer
        isSending = true
        defer { isSending = false }
        do {
            try await ComposerExecutor.send(
                method: composer.method,
                urlString: composer.url,
                headersBlock: composer.headers,
                bodyText: composer.body,
                viaProxyHost: appState.listenHost,
                viaProxyPort: appState.listenPort
            ) { snapshot in
                appState.sessions.ingest(snapshot)
            }
            statusMessage = "Request completed — see session list."
        } catch {
            appState.lastError = error.localizedDescription
            statusMessage = error.localizedDescription
        }
    }
}

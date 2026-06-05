//
//  BreakpointsEditorView.swift — Phase 4
//
//  Created by Shubhransh Gupta

import SwiftUI

struct BreakpointsEditorView: View {
    @Bindable var appState: AppState

    var body: some View {
        @Bindable var features = appState.features
        @Bindable var bp = features.breakpoints
        Form {
            Section {
                Text(bp.status).font(.caption).foregroundStyle(.secondary)
            }
            Section("Rules") {
                Toggle("Enable breakpoints", isOn: $bp.settings.isEnabled)
                    .onChange(of: bp.settings.isEnabled) { _, _ in appState.syncFeatureMailboxes() }
                Toggle("Break on request", isOn: $bp.settings.breakOnRequest)
                    .onChange(of: bp.settings.breakOnRequest) { _, _ in appState.syncFeatureMailboxes() }
                Toggle("Break on response", isOn: $bp.settings.breakOnResponse)
                    .onChange(of: bp.settings.breakOnResponse) { _, _ in appState.syncFeatureMailboxes() }
                TextField("URL regex (empty = all)", text: $bp.settings.urlPattern)
                    .font(.system(.body, design: .monospaced))
                    .onSubmit { appState.syncFeatureMailboxes() }
            }
            if !bp.pending.isEmpty {
                Section("Pending (\(bp.pending.count))") {
                    Button("Forward all") { bp.forwardAllAutomatic() }
                    Button("Cancel all", role: .destructive) { bp.cancelAll() }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Breakpoints")
    }
}

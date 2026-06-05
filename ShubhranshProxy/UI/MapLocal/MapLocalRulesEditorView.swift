//
//  MapLocalRulesEditorView.swift
//  ShubhranshProxy
//  Created by Shubhransh Gupta
//

import AppKit
import SwiftUI

struct MapLocalRulesEditorView: View {
    @Bindable var appState: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var sessions = appState.sessions
        NavigationStack {
            List {
                Section {
                    Text("Match the **full URL** (e.g. `https://api.example.com/v1/users`). Use plain text or regex. Rules apply immediately while the proxy is running.")
                        .font(.caption)
                }
                Section("Rules") {
                    ForEach($sessions.mapLocalRules) { rule in
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle("Enabled", isOn: rule.isEnabled)
                            TextField("URL contains or regex", text: rule.pattern)
                                .font(.system(.body, design: .monospaced))
                            if rule.wrappedValue.usesInlineBody {
                                Text("Inline response (\(rule.wrappedValue.inlineBody.count) chars)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else if let path = rule.wrappedValue.localFileURL?.path {
                                HStack {
                                    Text(path)
                                        .font(.caption)
                                        .lineLimit(2)
                                    Spacer()
                                    Button("Choose file…") { pickFile(binding: rule.localFileURL) }
                                }
                            } else {
                                Button("Choose file…") { pickFile(binding: rule.localFileURL) }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .onDelete { sessions.removeMapRules(at: $0); appState.syncMapLocalMailbox() }
                }
            }
            .navigationTitle("Map Local")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) {
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        appState.syncMapLocalMailbox()
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Add rule") {
                        sessions.addMapRule()
                        appState.syncMapLocalMailbox()
                    }
                }
            }
            .onDisappear {
                appState.syncMapLocalMailbox()
            }
        }
    }

    private func pickFile(binding: Binding<URL?>) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        if let win = NSApp.keyWindow ?? NSApp.mainWindow {
            panel.beginSheetModal(for: win) { result in
                if result == .OK, let url = panel.url {
                    binding.wrappedValue = url
                    appState.syncMapLocalMailbox()
                }
            }
        }
    }
}

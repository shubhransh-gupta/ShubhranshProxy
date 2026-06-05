//
//  RewriteRulesEditorView.swift — Phase 4
//
//  Created by Shubhransh Gupta

import SwiftUI

struct RewriteRulesEditorView: View {
    @Bindable var appState: AppState

    var body: some View {
        @Bindable var features = appState.features
        @Bindable var rewrite = features.rewrite
        NavigationStack {
            List {
                Section {
                    Toggle("Enable rewrite", isOn: $features.rewriteEnabled)
                        .onChange(of: features.rewriteEnabled) { _, _ in appState.syncFeatureMailboxes() }
                    Text(rewrite.status).font(.caption).foregroundStyle(.secondary)
                }
                Section("Rules") {
                    ForEach($rewrite.rules) { $rule in
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle("Enabled", isOn: $rule.isEnabled)
                            TextField("Name", text: $rule.name)
                            TextField("URL regex", text: $rule.urlPattern)
                                .font(.system(.caption, design: .monospaced))
                            Picker("Target", selection: $rule.target) {
                                ForEach(RewriteTarget.allCases) { t in
                                    Text(t.rawValue).tag(t)
                                }
                            }
                            TextField("Match regex", text: $rule.matchPattern)
                                .font(.system(.caption, design: .monospaced))
                            TextField("Replace with", text: $rule.replaceWith)
                                .font(.system(.caption, design: .monospaced))
                        }
                        .padding(.vertical, 4)
                    }
                    .onDelete { rewrite.remove(at: $0) }
                }
            }
            .navigationTitle("Rewrite")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Add rule") {
                        rewrite.addRule()
                        appState.syncFeatureMailboxes()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { appState.syncFeatureMailboxes() }
                }
            }
        }
    }
}

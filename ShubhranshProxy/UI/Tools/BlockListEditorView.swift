//
//  BlockListEditorView.swift — Phase 4
//
//  Created by Shubhransh Gupta

import SwiftUI

struct BlockListEditorView: View {
    @Bindable var appState: AppState

    var body: some View {
        @Bindable var features = appState.features
        @Bindable var block = features.blockList
        NavigationStack {
            List {
                Section {
                    Toggle("Enable block list", isOn: $features.blockListEnabled)
                        .onChange(of: features.blockListEnabled) { _, _ in appState.syncFeatureMailboxes() }
                    Text("Blocked requests return HTTP 403. Use regex or plain substring patterns.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("Domain patterns") {
                    ForEach(block.domainPatterns.indices, id: \.self) { index in
                        TextField("e.g. ads.example.com or .*tracker.*", text: $block.domainPatterns[index])
                            .font(.system(.caption, design: .monospaced))
                    }
                    .onDelete { block.removeDomain(at: $0) }
                    Button("Add domain pattern") { block.addDomainPattern() }
                }
                Section("Path / URL patterns") {
                    ForEach(block.pathPatterns.indices, id: \.self) { index in
                        TextField("e.g. /analytics or .*\\.gif$", text: $block.pathPatterns[index])
                            .font(.system(.caption, design: .monospaced))
                    }
                    .onDelete { block.removePath(at: $0) }
                    Button("Add path pattern") { block.addPathPattern() }
                }
            }
            .navigationTitle("Block List")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { appState.syncFeatureMailboxes() }
                }
            }
        }
    }
}

//
//  BreakpointSheetView.swift — Phase 4
//
//  Created by Shubhransh Gupta

import SwiftUI

struct BreakpointSheetView: View {
    @Bindable var appState: AppState

    var body: some View {
        @Bindable var features = appState.features
        @Bindable var bp = features.breakpoints
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                if let item = bp.pending.first(where: { $0.id == bp.selectedPendingId }) ?? bp.pending.first {
                    Text("\(item.phase.rawValue.capitalized) breakpoint")
                        .font(.headline)
                    Text(item.url).font(.caption.monospaced()).textSelection(.enabled)
                    Picker("Pending", selection: $bp.selectedPendingId) {
                        ForEach(bp.pending) { p in
                            Text("\(p.phase.rawValue) — \(p.method) \(p.host)").tag(Optional(p.id))
                        }
                    }
                    Text("Headers").font(.subheadline.weight(.semibold))
                    TextEditor(text: $bp.editedHeaders)
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: 120)
                    Text("Body").font(.subheadline.weight(.semibold))
                    TextEditor(text: $bp.editedBody)
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: 120)
                } else {
                    ContentUnavailableView("No pending breakpoints", systemImage: "pause.circle")
                }
                Spacer()
            }
            .padding()
            .navigationTitle("Breakpoint")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Drop") { bp.dropSelected() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Forward") { bp.forwardSelected() }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .frame(minWidth: 560, minHeight: 480)
    }
}

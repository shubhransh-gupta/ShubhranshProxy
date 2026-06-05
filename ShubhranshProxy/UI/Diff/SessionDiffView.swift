//
//  SessionDiffView.swift
//  ShubhranshProxy — UI (Phase 3)
//  Created by Shubhransh Gupta
//

import SwiftUI

struct SessionDiffView: View {
    @Environment(AppState.self) private var appState
    @State private var leftId: UUID?
    @State private var rightId: UUID?
    @State private var section: DiffSection = .overview

    enum DiffSection: String, CaseIterable, Identifiable {
        case overview = "Overview"
        case requestHeaders = "Req headers"
        case responseHeaders = "Res headers"
        case requestBody = "Req body"
        case responseBody = "Res body"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            pickerRow
            Divider()
            if let left = session(leftId), let right = session(rightId) {
                let diff = SessionDiffTool.compare(left, right)
                Picker("Section", selection: $section) {
                    ForEach(DiffSection.allCases) { s in
                        Text(s.rawValue).tag(s)
                    }
                }
                .pickerStyle(.segmented)
                .padding()

                ScrollView {
                    sectionContent(diff, left: left, right: right)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                ContentUnavailableView(
                    "Pick two sessions",
                    systemImage: "arrow.left.arrow.right",
                    description: Text("Choose a left and right session to compare headers and bodies.")
                )
            }
        }
        .navigationTitle("Diff Tool")
        .onAppear { seedFromSelection() }
    }

    private var pickerRow: some View {
        HStack(spacing: 16) {
            sessionPicker("Left", selection: $leftId)
            sessionPicker("Right", selection: $rightId)
            Button("Use selection") { seedFromSelection() }
                .disabled(appState.sessions.selectedSessionId == nil)
        }
        .padding()
    }

    private func sessionPicker(_ title: String, selection: Binding<UUID?>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.weight(.semibold))
            Picker(title, selection: selection) {
                Text("—").tag(UUID?.none)
                ForEach(appState.sessions.sessions.prefix(200)) { s in
                    Text("\(s.method) \(s.host) — \(s.statusLabel)")
                        .tag(Optional(s.id))
                }
            }
            .labelsHidden()
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func sectionContent(_ diff: SessionDiffTool.SessionDiff, left: ProxySession, right: ProxySession) -> some View {
        switch section {
        case .overview:
            overviewSection(diff.overview, left: left, right: right)
        case .requestHeaders:
            diffSection(diff.requestHeaders)
        case .responseHeaders:
            diffSection(diff.responseHeaders)
        case .requestBody:
            diffSection(diff.requestBody)
        case .responseBody:
            diffSection(diff.responseBody)
        }
    }

    private func overviewSection(_ rows: [(label: String, left: String, right: String, changed: Bool)], left: ProxySession, right: ProxySession) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Session A: \(left.method) \(left.url)").font(.caption.monospaced())
            Text("Session B: \(right.method) \(right.url)").font(.caption.monospaced())
            Divider()
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Text("Field").font(.caption.weight(.semibold))
                    Text("Left").font(.caption.weight(.semibold))
                    Text("Right").font(.caption.weight(.semibold))
                }
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        Text(row.label).font(.caption)
                        Text(row.left).font(.caption.monospaced())
                            .foregroundStyle(row.changed ? .orange : .primary)
                        Text(row.right).font(.caption.monospaced())
                            .foregroundStyle(row.changed ? .orange : .primary)
                    }
                }
            }
        }
    }

    private func diffSection(_ lines: [SessionDiffTool.DiffLine]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if lines.isEmpty {
                Text("No differences").foregroundStyle(.secondary)
            } else {
                ForEach(lines) { line in
                    Text(line.text)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(color(for: line.kind))
                        .textSelection(.enabled)
                }
            }
        }
    }

    private func color(for kind: SessionDiffTool.DiffLine.Kind) -> Color {
        switch kind {
        case .same: .primary
        case .added: .green
        case .removed: .red
        }
    }

    private func session(_ id: UUID?) -> ProxySession? {
        appState.sessions.session(id: id)
    }

    private func seedFromSelection() {
        guard let selected = appState.sessions.selectedSessionId else { return }
        if leftId == nil {
            leftId = selected
        } else if rightId == nil, leftId != selected {
            rightId = selected
        } else {
            rightId = selected
        }
    }
}

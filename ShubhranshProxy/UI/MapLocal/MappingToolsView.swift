//
//  MappingToolsView.swift
//  ShubhranshProxy
//
//  Created by Shubhransh Gupta
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

private enum MappingMode: String, CaseIterable, Identifiable {
    case mapLocal = "Map Local"
    case mapRemote = "Map Remote"
    case allMapped = "All Mapped"
    var id: String { rawValue }
}

private enum MappedRuleKind {
    case local
    case remote
}

private struct MappedURLListEntry: Identifiable {
    let id: UUID
    let kind: MappedRuleKind
    let matchPattern: String
    let destination: String?
    let isEnabled: Bool
    let detail: String
}

private enum MapLocalSource: String, CaseIterable, Identifiable {
    case paste = "Paste / Edit"
    case file = "Local File"
    var id: String { rawValue }
}

struct MappingToolsView: View {
    @Bindable var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var mode: MappingMode = .mapLocal
    @State private var localMatchURL = ""
    @State private var localSource: MapLocalSource = .paste
    @State private var localResponseBody = "{\n  \n}"
    @State private var localContentType = "application/json; charset=utf-8"
    @State private var localFileURL: URL?
    @State private var remoteFromURL = ""
    @State private var remoteToURL = ""
    @State private var mappedURLSearch = ""

    var body: some View {
        VStack(spacing: 0) {
            Picker("Tool", selection: $mode) {
                ForEach(MappingMode.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch mode {
                    case .mapLocal:
                        mapLocalGuide
                        mapLocalWizard
                        mapLocalRulesList
                    case .mapRemote:
                        mapRemoteGuide
                        mapRemoteWizard
                        mapRemoteRulesList
                    case .allMapped:
                        allMappedURLsView
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Map Local & Map Remote")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", role: .cancel) {
                    cancelMappingTools()
                }
                .keyboardShortcut(.cancelAction)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    finishMappingTools()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .safeAreaInset(edge: .bottom) {
            mappingToolsFooter
        }
        .onAppear(perform: applyPrefillIfNeeded)
        .onDisappear {
            appState.syncMappingMailboxes()
        }
    }

    private var mappingToolsFooter: some View {
        HStack {
            Button("Cancel", role: .cancel) {
                cancelMappingTools()
            }
            .keyboardShortcut(.cancelAction)

            Spacer()

            Button("Done") {
                finishMappingTools()
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func cancelMappingTools() {
        appState.dismissMappingTools()
        dismiss()
    }

    private func finishMappingTools() {
        appState.syncMappingMailboxes()
        appState.dismissMappingTools()
        dismiss()
    }

    private func applyPrefillIfNeeded() {
        guard let prefill = appState.consumeMappingToolsPrefill() else { return }
        switch prefill.mode {
        case .mapLocal:
            mode = .mapLocal
            localMatchURL = prefill.matchURL
            if !prefill.responseBody.isEmpty {
                localSource = .paste
                localResponseBody = prefill.responseBody
                localContentType = prefill.contentType
            }
        case .mapRemote:
            mode = .mapRemote
            remoteFromURL = prefill.matchURL
            remoteToURL = prefill.remoteToURL
        case .allMapped:
            mode = .allMapped
        }
    }

    // MARK: - Map Local

    private var mapLocalGuide: some View {
        GroupBox("Map Local — return a custom response") {
            VStack(alignment: .leading, spacing: 6) {
                stepRow(number: 1, text: "Pick a URL pattern from a captured request.")
                stepRow(number: 2, text: "Paste or edit the JSON/text response below — or choose a local file.")
                stepRow(number: 3, text: "Enable the rule. Matching requests return your body instantly.")
                Text("Tip: right-click a session → Map Local to prefill URL and response.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var mapLocalWizard: some View {
        GroupBox("Quick setup") {
            VStack(alignment: .leading, spacing: 10) {
                if let url = selectedSessionURL {
                    Button("Use selected session URL") {
                        localMatchURL = url
                    }
                    .font(.caption)
                }
                TextField("URL to match", text: $localMatchURL, prompt: Text("https://api.example.com/v1/profile"))
                    .textFieldStyle(.roundedBorder)

                Picker("Response source", selection: $localSource) {
                    ForEach(MapLocalSource.allCases) { source in
                        Text(source.rawValue).tag(source)
                    }
                }
                .pickerStyle(.segmented)

                switch localSource {
                case .paste:
                    mapLocalResponseEditor(body: $localResponseBody, contentType: $localContentType, compact: false)
                case .file:
                    HStack {
                        Text(localFileURL?.lastPathComponent ?? "No file chosen")
                            .font(.caption)
                            .lineLimit(1)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Choose file…") { pickLocalFile() }
                    }
                }

                Button("Add Map Local rule") {
                    addMapLocalRule()
                }
                .disabled(!canAddMapLocalRule)

                Text("Add as many URL rules as you need — there is no limit.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var mapLocalRulesList: some View {
        @Bindable var sessions = appState.sessions
        return rulesListBox(
            title: "Active Map Local rules",
            count: sessions.mapLocalRules.count,
            emptyMessage: "No Map Local rules yet."
        ) {
            ForEach($sessions.mapLocalRules) { rule in
                mapLocalRuleEditor(rule)
                Divider()
            }
            .onDelete { sessions.removeMapRules(at: $0); appState.syncMappingMailboxes() }
        }
    }

    @ViewBuilder
    private func mapLocalRuleEditor(_ rule: Binding<MapLocalRule>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Toggle("Enabled", isOn: rule.isEnabled)
                Spacer()
                Button("Remove", role: .destructive) {
                    appState.sessions.removeMapLocalRule(id: rule.wrappedValue.id)
                    appState.syncMappingMailboxes()
                }
                .buttonStyle(.link)
                .font(.caption)
            }
            TextField("Match URL", text: rule.pattern)
                .textFieldStyle(.roundedBorder)

            if rule.wrappedValue.usesInlineBody {
                mapLocalResponseEditor(body: rule.inlineBody, contentType: rule.contentType, compact: true)
                Button("Switch to file…") {
                    pickLocalFile(into: rule.localFileURL)
                    rule.wrappedValue.inlineBody = ""
                }
                .font(.caption)
            } else if let fileURL = rule.wrappedValue.localFileURL {
                HStack {
                    Text(fileURL.lastPathComponent)
                        .font(.caption)
                        .lineLimit(1)
                    Spacer()
                    Button("Change file…") { pickLocalFile(into: rule.localFileURL) }
                    Button("Paste response instead") {
                        rule.wrappedValue.inlineBody = "{\n  \n}"
                        rule.wrappedValue.contentType = "application/json; charset=utf-8"
                    }
                    .font(.caption)
                }
            } else {
                Button("Paste response") {
                    rule.wrappedValue.inlineBody = "{\n  \n}"
                }
                .font(.caption)
            }
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func mapLocalResponseEditor(
        body: Binding<String>,
        contentType: Binding<String>,
        compact: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button("Paste") { pasteInto(body) }
                Button("Use selected response") { importSelectedResponse(into: body, contentType: contentType) }
                Button("Format JSON") { formatJSON(in: body) }
                Spacer()
            }
            .font(.caption)

            Picker("Content-Type", selection: contentType) {
                Text("JSON").tag("application/json; charset=utf-8")
                Text("HTML").tag("text/html; charset=utf-8")
                Text("Plain text").tag("text/plain; charset=utf-8")
            }
            .pickerStyle(.segmented)

            TextEditor(text: body)
                .font(.system(.footnote, design: .monospaced))
                .frame(minHeight: compact ? 120 : 180, maxHeight: compact ? 180 : 260)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.25))
                )
        }
    }

    // MARK: - Map Remote

    private var mapRemoteGuide: some View {
        GroupBox("Map Remote — redirect to another server") {
            VStack(alignment: .leading, spacing: 6) {
                stepRow(number: 1, text: "Find the API URL you want to reroute (e.g. production host).")
                stepRow(number: 2, text: "Set **From** to that URL or host fragment.")
                stepRow(number: 3, text: "Set **To** to the staging/local server URL (same path is kept).")
                stepRow(number: 4, text: "Enable the rule — requests hit the new server but appear in the session list.")
            }
        }
    }

    private var mapRemoteWizard: some View {
        GroupBox("Quick setup") {
            VStack(alignment: .leading, spacing: 10) {
                if let url = selectedSessionURL {
                    Button("Use selected session URL as From") {
                        remoteFromURL = url
                    }
                    .font(.caption)
                }
                TextField("From (match)", text: $remoteFromURL, prompt: Text("https://api.prod.com"))
                    .textFieldStyle(.roundedBorder)
                TextField("To (redirect)", text: $remoteToURL, prompt: Text("https://api.staging.com"))
                    .textFieldStyle(.roundedBorder)
                Button("Add Map Remote rule") {
                    addMapRemoteRule()
                }
                .disabled(
                    remoteFromURL.trimmingCharacters(in: .whitespaces).isEmpty
                        || remoteToURL.trimmingCharacters(in: .whitespaces).isEmpty
                )

                Text("Add as many redirect rules as you need — there is no limit.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var mapRemoteRulesList: some View {
        @Bindable var sessions = appState.sessions
        return rulesListBox(
            title: "Active Map Remote rules",
            count: sessions.mapRemoteRules.count,
            emptyMessage: "No Map Remote rules yet."
        ) {
            ForEach($sessions.mapRemoteRules) { rule in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Toggle("Enabled", isOn: rule.isEnabled)
                        Spacer()
                        Button("Remove", role: .destructive) {
                            appState.sessions.removeMapRemoteRule(id: rule.wrappedValue.id)
                            appState.syncMappingMailboxes()
                        }
                        .buttonStyle(.link)
                        .font(.caption)
                    }
                    TextField("From", text: rule.sourcePattern)
                        .textFieldStyle(.roundedBorder)
                    TextField("To", text: rule.destinationPattern)
                        .textFieldStyle(.roundedBorder)
                }
                .padding(.vertical, 4)
                Divider()
            }
            .onDelete { sessions.removeMapRemoteRules(at: $0); appState.syncMappingMailboxes() }
        }
    }

    // MARK: - All Mapped URLs

    private var allMappedURLsView: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox("All mapped URLs") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Every Map Local and Map Remote rule in one place. Search, enable, edit, or remove any mapped URL.")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 16) {
                        mappedStat(label: "Map Local", value: appState.sessions.mapLocalRules.count)
                        mappedStat(label: "Map Remote", value: appState.sessions.mapRemoteRules.count)
                        mappedStat(label: "Enabled", value: appState.enabledMappedRuleCount)
                    }

                    TextField("Search mapped URLs", text: $mappedURLSearch)
                        .textFieldStyle(.roundedBorder)
                }
            }

            GroupBox {
                if filteredMappedEntries.isEmpty {
                    Text(mappedURLSearch.isEmpty ? "No mapped URLs yet. Use Map Local or Map Remote to add rules." : "No mapped URLs match your search.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                } else {
                    List {
                        ForEach(filteredMappedEntries) { entry in
                            mappedURLRow(entry)
                        }
                    }
                    .frame(minHeight: 280, maxHeight: 420)
                }
            } label: {
                HStack {
                    Text("Mapped URL list")
                    Spacer()
                    Text("\(filteredMappedEntries.count) shown")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 12) {
                Button("Add Map Local…") { mode = .mapLocal }
                Button("Add Map Remote…") { mode = .mapRemote }
                Spacer()
                Button("Copy all URLs") { copyAllMappedURLs() }
                    .disabled(allMappedEntries.isEmpty)
            }
            .font(.caption)
        }
    }

    private func mappedStat(label: String, value: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.title3.bold().monospacedDigit())
        }
    }

    @ViewBuilder
    private func mappedURLRow(_ entry: MappedURLListEntry) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: entry.kind == .local ? "doc.on.doc.fill" : "arrow.triangle.swap")
                .foregroundStyle(entry.kind == .local ? .orange : .blue)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.matchPattern)
                    .font(.callout)
                    .lineLimit(2)
                    .textSelection(.enabled)
                if let destination = entry.destination, !destination.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.right")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(destination)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .textSelection(.enabled)
                    }
                }
                Text(entry.detail)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 8)

            Toggle("", isOn: mappedEnabledBinding(for: entry))
                .toggleStyle(.switch)
                .labelsHidden()

            Menu {
                Button("Edit in Map Local") {
                    mode = .mapLocal
                }
                .disabled(entry.kind != .local)
                Button("Edit in Map Remote") {
                    mode = .mapRemote
                }
                .disabled(entry.kind != .remote)
                Button("Copy URL") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(entry.matchPattern, forType: .string)
                }
                Divider()
                Button("Remove", role: .destructive) {
                    removeMappedEntry(entry)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 24)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func rulesListBox<Content: View>(
        title: String,
        count: Int,
        emptyMessage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        GroupBox {
            if count == 0 {
                Text(emptyMessage)
                    .foregroundStyle(.secondary)
            } else {
                List {
                    content()
                }
                .frame(minHeight: min(360, CGFloat(count) * 120 + 40), maxHeight: 420)
            }
        } label: {
            HStack {
                Text(title)
                Spacer()
                Text("\(count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Helpers

    private var canAddMapLocalRule: Bool {
        guard !localMatchURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        switch localSource {
        case .paste:
            return !localResponseBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .file:
            return localFileURL != nil
        }
    }

    private var selectedSessionURL: String? {
        selectedSession?.url
    }

    private var selectedSession: ProxySession? {
        guard let id = appState.sessions.selectedSessionId else { return nil }
        return appState.sessions.session(id: id)
    }

    private func stepRow(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(number).")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .frame(width: 16, alignment: .trailing)
            Text(text)
                .font(.callout)
        }
    }

    private func pasteInto(_ target: Binding<String>) {
        if let text = NSPasteboard.general.string(forType: .string), !text.isEmpty {
            target.wrappedValue = text
        }
    }

    private func importSelectedResponse(into body: Binding<String>, contentType: Binding<String>) {
        guard let session = selectedSession else { return }
        if let response = session.responseBody, !response.isEmpty {
            body.wrappedValue = BodyFormatting.displayText(response)
            if let mime = session.mimeType?.lowercased() {
                if mime.contains("json") {
                    contentType.wrappedValue = "application/json; charset=utf-8"
                } else if mime.contains("html") {
                    contentType.wrappedValue = "text/html; charset=utf-8"
                } else {
                    contentType.wrappedValue = "text/plain; charset=utf-8"
                }
            }
        }
    }

    private func formatJSON(in body: Binding<String>) {
        guard let data = body.wrappedValue.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: pretty, encoding: .utf8) else { return }
        body.wrappedValue = text
    }

    private func pickLocalFile(into binding: Binding<URL?>? = nil) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.json, .text, .html, .xml, .data]
        if let win = NSApp.keyWindow ?? NSApp.mainWindow {
            panel.beginSheetModal(for: win) { result in
                guard result == .OK, let url = panel.url else { return }
                if let binding {
                    binding.wrappedValue = url
                } else {
                    localFileURL = url
                }
                appState.syncMappingMailboxes()
            }
        }
    }

    private func addMapLocalRule() {
        let pattern = localMatchURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let rule: MapLocalRule
        switch localSource {
        case .paste:
            rule = MapLocalRule(
                pattern: pattern,
                inlineBody: localResponseBody,
                contentType: localContentType,
                isEnabled: true
            )
        case .file:
            guard let file = localFileURL else { return }
            rule = MapLocalRule(pattern: pattern, localFileURL: file, isEnabled: true)
        }
        appState.sessions.addMapLocalRule(rule)
        localMatchURL = ""
        localResponseBody = "{\n  \n}"
        localFileURL = nil
        appState.syncMappingMailboxes()
    }

    private func addMapRemoteRule() {
        let rule = MapRemoteRule(
            sourcePattern: remoteFromURL.trimmingCharacters(in: .whitespacesAndNewlines),
            destinationPattern: remoteToURL.trimmingCharacters(in: .whitespacesAndNewlines),
            isEnabled: true
        )
        appState.sessions.addMapRemoteRule(rule)
        remoteFromURL = ""
        remoteToURL = ""
        appState.syncMappingMailboxes()
    }

    private var allMappedEntries: [MappedURLListEntry] {
        let local = appState.sessions.mapLocalRules.map { rule in
            MappedURLListEntry(
                id: rule.id,
                kind: .local,
                matchPattern: rule.pattern,
                destination: nil,
                isEnabled: rule.isEnabled,
                detail: mapLocalDetail(for: rule)
            )
        }
        let remote = appState.sessions.mapRemoteRules.map { rule in
            MappedURLListEntry(
                id: rule.id,
                kind: .remote,
                matchPattern: rule.sourcePattern,
                destination: rule.destinationPattern,
                isEnabled: rule.isEnabled,
                detail: "Map Remote redirect"
            )
        }
        return (local + remote).sorted {
            $0.matchPattern.localizedCaseInsensitiveCompare($1.matchPattern) == .orderedAscending
        }
    }

    private var filteredMappedEntries: [MappedURLListEntry] {
        guard !mappedURLSearch.isEmpty else { return allMappedEntries }
        return allMappedEntries.filter { entry in
            entry.matchPattern.localizedCaseInsensitiveContains(mappedURLSearch)
                || (entry.destination?.localizedCaseInsensitiveContains(mappedURLSearch) ?? false)
                || entry.detail.localizedCaseInsensitiveContains(mappedURLSearch)
        }
    }

    private func mapLocalDetail(for rule: MapLocalRule) -> String {
        if rule.usesInlineBody {
            return "Map Local · \(rule.contentType)"
        }
        if let fileURL = rule.localFileURL {
            return "Map Local · file · \(fileURL.lastPathComponent)"
        }
        return "Map Local · no response configured"
    }

    private func mappedEnabledBinding(for entry: MappedURLListEntry) -> Binding<Bool> {
        Binding(
            get: { entry.isEnabled },
            set: { enabled in
                switch entry.kind {
                case .local:
                    guard let index = appState.sessions.mapLocalRules.firstIndex(where: { $0.id == entry.id }) else { return }
                    appState.sessions.mapLocalRules[index].isEnabled = enabled
                case .remote:
                    guard let index = appState.sessions.mapRemoteRules.firstIndex(where: { $0.id == entry.id }) else { return }
                    appState.sessions.mapRemoteRules[index].isEnabled = enabled
                }
                appState.syncMappingMailboxes()
            }
        )
    }

    private func removeMappedEntry(_ entry: MappedURLListEntry) {
        switch entry.kind {
        case .local:
            appState.sessions.removeMapLocalRule(id: entry.id)
        case .remote:
            appState.sessions.removeMapRemoteRule(id: entry.id)
        }
        appState.syncMappingMailboxes()
    }

    private func copyAllMappedURLs() {
        let lines = allMappedEntries.map { entry in
            if let destination = entry.destination, !destination.isEmpty {
                return "\(entry.matchPattern) -> \(destination)"
            }
            return entry.matchPattern
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
    }
}

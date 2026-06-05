//
//  SessionInspectorView.swift — Proxyman-style bottom inspector panel
//
//  Created by Shubhransh Gupta

import AppKit
import SwiftUI

enum InspectorTab: String, CaseIterable, Identifiable {
    case summary = "Summary"
    case request = "Request"
    case response = "Response"
    case headers = "Headers"
    var id: String { rawValue }
}

struct SessionInspectorView: View {
    @Environment(AppState.self) private var appState
    let selectedSessionId: UUID?
    @State private var tab: InspectorTab = .response
    @State private var requestBodyFormat: BodyDisplayFormat = .text
    @State private var responseBodyFormat: BodyDisplayFormat = .json

    private var session: ProxySession? {
        appState.sessions.session(id: selectedSessionId)
    }

    var body: some View {
        Group {
            if let session {
                inspectorContent(for: session)
                    .id(session.id)
            } else {
                ContentUnavailableView(
                    "No Selection",
                    systemImage: "magnifyingglass",
                    description: Text("Select a request above to inspect request and response.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func inspectorContent(for session: ProxySession) -> some View {
        VStack(spacing: 0) {
            inspectorHeader(session)
            Divider()
            Picker("Panel", selection: $tab) {
                ForEach(InspectorTab.allCases) { t in
                    Text(t.rawValue).tag(t)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            ScrollView {
                tabContent(session)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(.background)
        .onAppear {
            resetInspectorState(for: session)
        }
    }

    private func resetInspectorState(for session: ProxySession) {
        tab = .response
        applySuggestedFormats(session)
    }

    private func inspectorHeader(_ s: ProxySession) -> some View {
        HStack(spacing: 10) {
            Text(s.method)
                .font(.caption.bold().monospaced())
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.accentColor.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 4))

            Text(APITrafficCatalog.pathWithoutQuery(from: s.url))
                .font(.callout)
                .lineLimit(1)

            if let status = s.responseStatus {
                Text("\(status)")
                    .font(.caption.bold().monospaced())
                    .foregroundStyle(statusColor(status))
            }

            Spacer()

            if let ms = s.durationMs {
                Text(String(format: "%.0f ms", ms))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if let size = s.responseSize {
                Text(byteLabel(size))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    @ViewBuilder
    private func tabContent(_ s: ProxySession) -> some View {
        switch tab {
        case .summary:
            summaryTab(s)
        case .request:
            bodySection(title: "Request", data: s.requestBody, format: $requestBodyFormat, mime: nil, url: s.url)
        case .response:
            responseTab(s)
        case .headers:
            headersTab(s)
        }
    }

    private func responseTab(_ s: ProxySession) -> some View {
        Group {
            if s.isCONNECT {
                Text("Encrypted tunnel — enable SSL Proxying for this host.")
                    .foregroundStyle(.secondary)
            } else if let body = s.responseBody, !body.isEmpty {
                bodySection(title: "Response", data: body, format: $responseBodyFormat, mime: s.mimeType, url: s.url)
            } else if s.responseStatus != nil {
                Text("Response received with no body (status \(s.statusLabel)).")
                    .foregroundStyle(.secondary)
            } else if let err = s.errorMessage {
                Text(err).foregroundStyle(.red)
            } else {
                Text("Waiting for response…")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func summaryTab(_ s: ProxySession) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            LabeledContent("URL", value: s.url)
            LabeledContent("Host", value: s.host)
            if let mime = s.mimeType { LabeledContent("MIME", value: mime) }
            if s.wasDecryptedHTTPS { Label("HTTPS (decrypted)", systemImage: "lock.open.fill").foregroundStyle(.green) }
            if s.wasMappedLocal { Label("Map Local", systemImage: "doc.on.doc").foregroundStyle(.orange) }
            if s.wasMappedRemote { Label("Map Remote", systemImage: "arrow.triangle.swap").foregroundStyle(.blue) }
        }
        .font(.callout)
    }

    private func headersTab(_ s: ProxySession) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Request").font(.caption.weight(.semibold))
            monoBlock(s.requestHeaders)
            Text("Response").font(.caption.weight(.semibold))
            if let h = s.responseHeaders { monoBlock(h) } else { Text("(none)").foregroundStyle(.secondary) }
        }
    }

    @ViewBuilder
    private func bodySection(
        title: String,
        data: Data,
        format: Binding<BodyDisplayFormat>,
        mime: String?,
        url: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.caption.weight(.semibold))
                Spacer()
                Picker("Format", selection: format) {
                    ForEach(BodyDisplayFormat.choices(for: mime)) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 280)
            }
            if data.isEmpty {
                Text("(empty)").foregroundStyle(.secondary)
            } else {
                bodyText(data: data, format: format.wrappedValue, mime: mime, url: url)
            }
        }
    }

    @ViewBuilder
    private func bodyText(data: Data, format: BodyDisplayFormat, mime: String?, url: String) -> some View {
        switch format {
        case .html:
            if BodyFormatting.looksLikeHTML(data, mime: mime) {
                HTMLPreviewView(html: BodyFormatting.displayText(data), baseURL: baseURL(from: url))
                    .frame(minHeight: 160, maxHeight: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                monoBlock(BodyFormatting.displayText(data))
            }
        case .text:
            monoBlock(BodyFormatting.displayText(data))
        case .json:
            monoBlock(BodyFormatting.jsonModeDisplay(data))
        case .hex:
            monoBlock(BodyFormatting.hexDump(data))
        }
    }

    private func monoBlock(_ text: String) -> some View {
        Text(text)
            .font(.system(.footnote, design: .monospaced))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func applySuggestedFormats(_ s: ProxySession) {
        if let mime = s.mimeType?.lowercased() {
            if mime.contains("json") {
                responseBodyFormat = .json
            } else if mime.contains("html") {
                responseBodyFormat = .html
            } else {
                responseBodyFormat = .text
            }
        } else if let body = s.responseBody, BodyFormatting.looksLikeJSON(body) {
            responseBodyFormat = .json
        } else {
            responseBodyFormat = .text
        }

        if BodyFormatting.looksLikeJSON(s.requestBody) {
            requestBodyFormat = .json
        } else {
            requestBodyFormat = .text
        }
    }

    private func statusColor(_ code: Int) -> Color {
        switch code {
        case 200..<300: .green
        case 400..<500: .orange
        case 500...: .red
        default: .primary
        }
    }

    private func byteLabel(_ n: Int) -> String {
        if n < 1024 { return "\(n) B" }
        return String(format: "%.1f KB", Double(n) / 1024)
    }

    private func baseURL(from urlString: String?) -> URL? {
        guard let urlString, let url = URL(string: urlString) else { return nil }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        components.path = (components.path as NSString).deletingLastPathComponent
        if components.path.isEmpty { components.path = "/" }
        return components.url
    }
}

//
//  SessionTableView.swift — Proxyman-style request list
//
//  Created by Shubhransh Gupta

import SwiftUI

struct SessionTableView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var sessions = appState.sessions
        Table(appState.sessionsForTable, selection: $sessions.selectedSessionId) {
            TableColumn("URL") { session in
                Text(APITrafficCatalog.pathWithoutQuery(from: session.url))
                    .lineLimit(1)
                    .help(session.url)
            }

            TableColumn("Client") { session in
                Text(TrafficDeviceCatalog.clientDisplayName(for: session))
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundStyle(clientColor(for: session))
            }
            .width(min: 80, ideal: 140)

            TableColumn("Method") { session in
                HTTPMethodStyle.badge(session.method)
            }
            .width(min: 52, ideal: 72)

            TableColumn("Status") { session in
                Text(session.statusLabel)
                    .font(.caption.bold().monospaced())
                    .foregroundStyle(statusColor(for: session))
            }
            .width(52)

            TableColumn("Time") { session in
                Text(session.startedDate, format: .dateTime.hour().minute().second())
                    .font(.caption.monospacedDigit())
            }
            .width(72)

            TableColumn("Duration") { session in
                if let ms = session.durationMs {
                    Text(String(format: "%.0f ms", ms))
                        .font(.caption.monospacedDigit())
                } else {
                    Text("—")
                }
            }
            .width(72)
        }
        .contextMenu(forSelectionType: UUID.self) { ids in
            if let id = ids.first, let session = appState.sessions.session(id: id) {
                sessionContextMenu(session)
            }
        }
    }

    @ViewBuilder
    private func sessionContextMenu(_ session: ProxySession) -> some View {
        Button("Copy cURL") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(HARExporter.exportCURL(session: session), forType: .string)
        }
        Button("Copy URL") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(session.url, forType: .string)
        }
        Divider()
        if !appState.tls.sslSettings.interceptAllHosts {
            if appState.isDecryptEnabled(for: session.host) {
                Button("Stop decrypting HTTPS for \(session.host)") {
                    appState.removeDecryptHost(session.host)
                }
            } else {
                Button("Decrypt HTTPS for \(session.host)") {
                    appState.addDecryptHost(session.host)
                }
            }
            Divider()
        }
        Button(appState.features.favorites.isFavorite(session.host) ? "Unpin domain" : "Pin domain") {
            appState.features.favorites.toggle(session.host)
        }
        Button(appState.features.favorites.isFavoriteEndpoint(session.url) ? "Unpin endpoint" : "Pin endpoint") {
            appState.features.favorites.toggleEndpoint(session.url)
        }
        Button("Map Local…") {
            let body = session.responseBody.map { BodyFormatting.displayText($0) } ?? ""
            let mime = session.mimeType ?? "application/json; charset=utf-8"
            appState.presentMappingTools(
                prefill: MappingToolsPrefill(
                    mode: .mapLocal,
                    matchURL: session.url,
                    responseBody: body,
                    contentType: mime.contains("json") ? "application/json; charset=utf-8" : mime
                )
            )
        }
        Button("Map Remote…") {
            appState.presentMappingTools(prefill: MappingToolsPrefill(mode: .mapRemote, matchURL: session.url))
        }
    }

    private func statusColor(for session: ProxySession) -> Color {
        if session.method == "TLS" || session.errorMessage != nil {
            return .pink
        }
        return statusColor(session.responseStatus)
    }

    private func clientColor(for session: ProxySession) -> Color {
        if let ip = session.clientIPAddress, !ClientAddressResolver.isLoopback(ip) {
            return .mint
        }
        return .secondary
    }

    private func statusColor(_ code: Int?) -> Color {
        guard let code else { return .secondary }
        switch code {
        case 200..<300: return .green
        case 300..<400: return .blue
        case 400..<500: return .orange
        case 500...: return .red
        default: return .primary
        }
    }
}

import AppKit

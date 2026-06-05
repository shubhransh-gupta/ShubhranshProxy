//
//  ProxyToolbar.swift
//  ShubhranshProxy
//  Created by Shubhransh Gupta
//
//  Supplementary toolbar — primary controls live in CaptureControlStrip (always visible in-window).
//

import SwiftUI

struct ProxyToolbar: ToolbarContent {
    @Environment(AppState.self) private var appState
    @Binding var showSetup: Bool

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button {
                appState.returnToCaptureHome()
            } label: {
                Label("Capture", systemImage: "list.bullet.rectangle")
            }
            .help("Return to session list")
        }

        ToolbarItem(placement: .principal) {
            Text(appState.compactCaptureStatus)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .help(appState.detailedCaptureStatus)
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                Task { await appState.toggleProxy() }
            } label: {
                Label(appState.isRunning ? "Stop" : "Start", systemImage: appState.isRunning ? "stop.circle.fill" : "play.circle.fill")
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .help(appState.isRunning ? "Stop capture" : "Start capture")
        }
    }
}

//
//  MainWindowView.swift
//  ShubhranshProxy
//  Created by Shubhransh Gupta
//

import SwiftUI

struct MainWindowView: View {
    @Environment(AppState.self) private var appState
    @State private var showSetup = false
    @State private var showBreakpointSheet = false

    var body: some View {
        @Bindable var state = appState
        VStack(spacing: 0) {
            CaptureControlStrip(showSetup: $showSetup)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.bar)
            Divider()
            NavigationSplitView {
                ProxySidebarView()
                    .navigationSplitViewColumnWidth(min: 300, ideal: 340, max: 420)
            } detail: {
                CaptureWorkspaceView()
            }
        }
        .navigationTitle("ShubhranshProxy")
        .toolbar { ProxyToolbar(showSetup: $showSetup) }
        .sheet(isPresented: $state.showMappingToolsSheet) {
            NavigationStack {
                MappingToolsView(appState: state)
            }
            .frame(minWidth: 680, minHeight: 620)
        }
        .onChange(of: state.showMappingToolsSheet) { _, isPresented in
            if !isPresented {
                state.syncMappingMailboxes()
            }
        }
        .sheet(isPresented: $showSetup) {
            SetupGuideView()
                .frame(minWidth: 760, minHeight: 720)
        }
        .sheet(isPresented: $showBreakpointSheet) {
            BreakpointSheetView(appState: state)
        }
        .onChange(of: appState.features.breakpoints.pending.count) { _, count in
            showBreakpointSheet = count > 0
        }
    }
}

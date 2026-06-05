//
//  ShubhranshProxyApp.swift
//  ShubhranshProxy
//  Created by Shubhransh Gupta
//

import SwiftUI

@main
struct ShubhranshProxyApp: App {
    @State private var appState = AppState()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            MainWindowView()
                .environment(appState)
                .frame(minWidth: 1100, minHeight: 700)
                .onAppear {
                    appDelegate.appState = appState
                }
        }
        .windowToolbarStyle(.unified(showsTitle: true))
    }
}

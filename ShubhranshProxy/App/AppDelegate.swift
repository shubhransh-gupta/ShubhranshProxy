//
//  AppDelegate.swift
//  ShubhranshProxy
//  Created by Shubhransh Gupta
//

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var appState: AppState?

    /// Quit when the main window closes so proxy cleanup always runs (Proxyman/Charles-style).
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        guard let appState else { return }
        MainActor.assumeIsolated {
            appState.performTerminationCleanup()
        }
    }
}

//
//  AppDelegate.swift
//  ShubhranshProxy
//  Created by Shubhransh Gupta
//

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var appState: AppState?

    func applicationWillTerminate(_ notification: Notification) {
        guard let appState else { return }
        MainActor.assumeIsolated {
            appState.performTerminationCleanup()
        }
    }
}

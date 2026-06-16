//
//  AppDelegate.swift
//  ShubhranshProxy
//  Created by Shubhransh Gupta
//

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var appState: AppState?
    private var isHandlingQuitConfirmation = false

    /// Quit when the main window closes so proxy cleanup always runs (Proxyman/Charles-style).
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let appState else { return .terminateNow }
        if isHandlingQuitConfirmation || appState.quitCleanupFinished {
            return .terminateNow
        }

        let needsConfirmation = MainActor.assumeIsolated {
            appState.needsQuitConfirmation
        }
        guard needsConfirmation else {
            return .terminateNow
        }

        let alert = NSAlert()
        alert.messageText = "Stop capture and quit?"
        alert.informativeText = """
        ShubhranshProxy is still capturing traffic. The proxy will be stopped and macOS Wi‑Fi proxy settings will be restored before the app closes.
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Stop and Quit")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else {
            return .terminateCancel
        }

        isHandlingQuitConfirmation = true
        Task { @MainActor in
            await appState.prepareForApplicationQuit()
            NSApplication.shared.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        guard let appState else { return }
        MainActor.assumeIsolated {
            if !appState.quitCleanupFinished {
                appState.performTerminationCleanup()
            }
        }
    }
}

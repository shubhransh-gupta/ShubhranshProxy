//
//  ExportHelpers.swift
//  ShubhranshProxy
//  Created by Shubhransh Gupta
//

import AppKit
import Foundation
import UniformTypeIdentifiers

enum ExportHelpers {
    @MainActor
    static func saveHAR(_ data: Data, defaultName: String) {
        let panel = makeSavePanel(defaultName: defaultName, contentTypes: [.json])
        presentSave(panel) { url in
            try? data.write(to: url, options: .atomic)
        }
    }

    @MainActor
    static func pickHAR(completion: @escaping (Data?) -> Void) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        presentOpen(panel) { url in
            completion(try? Data(contentsOf: url))
        }
    }

    @MainActor
    static func saveCertificate(from tempURL: URL, defaultName: String) {
        let ext = (defaultName as NSString).pathExtension.lowercased()
        let types: [UTType]
        switch ext {
        case "pem":
            types = [UTType(filenameExtension: "pem") ?? .plainText]
        case "cer", "crt":
            types = [UTType(filenameExtension: "cer") ?? .data]
        default:
            types = [.data]
        }

        let panel = makeSavePanel(defaultName: defaultName, contentTypes: types)
        presentSave(panel) { url in
            do {
                if FileManager.default.fileExists(atPath: url.path) {
                    try FileManager.default.removeItem(at: url)
                }
                try FileManager.default.copyItem(at: tempURL, to: url)
            } catch {
                NSApp.presentError(error)
            }
        }
    }

    @MainActor
    static func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// Sends a file via AirDrop. Returns an error message when AirDrop is unavailable.
    @MainActor
    @discardableResult
    static func shareViaAirDrop(fileURL: URL) -> String? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return "Certificate file was not found."
        }

        guard let service = NSSharingService(named: .sendViaAirDrop) else {
            return "AirDrop is not available on this Mac."
        }

        guard service.canPerform(withItems: [fileURL]) else {
            return "AirDrop cannot send the certificate right now. Turn on Wi‑Fi and Bluetooth, then try again."
        }

        service.perform(withItems: [fileURL])
        return nil
    }

    @MainActor
    static func saveJSON(_ data: Data, defaultName: String) {
        let panel = makeSavePanel(defaultName: defaultName, contentTypes: [.json])
        presentSave(panel) { url in
            try? data.write(to: url, options: .atomic)
        }
    }

    @MainActor
    static func pickJSON(completion: @escaping (Data?) -> Void) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        presentOpen(panel) { url in
            completion(try? Data(contentsOf: url))
        }
    }

    @MainActor
    private static func makeSavePanel(defaultName: String, contentTypes: [UTType]) -> NSSavePanel {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSSavePanel()
        panel.allowedContentTypes = contentTypes
        panel.nameFieldStringValue = defaultName
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.title = "Export"
        return panel
    }

    @MainActor
    private static func presentSave(_ panel: NSSavePanel, onURL: @escaping (URL) -> Void) {
        NSApp.activate(ignoringOtherApps: true)
        if let win = keyWindow {
            panel.beginSheetModal(for: win) { response in
                if response == .OK, let url = panel.url {
                    onURL(url)
                }
            }
            return
        }
        if panel.runModal() == .OK, let url = panel.url {
            onURL(url)
        }
    }

    @MainActor
    private static func presentOpen(_ panel: NSOpenPanel, onURL: @escaping (URL) -> Void) {
        NSApp.activate(ignoringOtherApps: true)
        if let win = keyWindow {
            panel.beginSheetModal(for: win) { response in
                guard response == .OK, let url = panel.url else { return }
                onURL(url)
            }
            return
        }
        if panel.runModal() == .OK, let url = panel.url {
            onURL(url)
        }
    }

    @MainActor
    private static var keyWindow: NSWindow? {
        NSApp.keyWindow
            ?? NSApp.mainWindow
            ?? NSApp.windows.first(where: { $0.isVisible && $0.isKeyWindow })
            ?? NSApp.windows.first(where: { $0.isVisible })
    }
}

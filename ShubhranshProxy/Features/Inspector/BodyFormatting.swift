//
//  BodyFormatting.swift
//  ShubhranshProxy — Features/Inspector
//  Created by Shubhransh Gupta
//

import Foundation

enum BodyDisplayFormat: String, CaseIterable, Identifiable {
    case text = "Text"
    case json = "JSON"
    case html = "Preview"
    case hex = "Hex"
    var id: String { rawValue }

    static func choices(for mime: String?) -> [BodyDisplayFormat] {
        if let mime, mime.contains("html") {
            return [.html, .text, .json, .hex]
        }
        return [.text, .json, .hex]
    }
}

enum BodyFormatting {
    static func trimmedForJSONProbe(_ data: Data) -> Data {
        var d = data
        while let b = d.first, b == 0x20 || b == 0x09 || b == 0x0A || b == 0x0D {
            d.removeFirst()
        }
        if d.count >= 3, d[0] == 0xEF, d[1] == 0xBB, d[2] == 0xBF {
            d.removeSubrange(0..<3)
        }
        return d
    }

    static func looksLikeJSON(_ data: Data) -> Bool {
        let d = trimmedForJSONProbe(data)
        guard let c = d.first else { return false }
        return c == UInt8(ascii: "{") || c == UInt8(ascii: "[")
    }

    static let maxInspectorBytes = 256 * 1024

    static func utf8Text(_ data: Data) -> String {
        displayText(data)
    }

    /// Safe inspector text — caps size so large/gzip bodies do not freeze the UI.
    static func displayText(_ data: Data, maxBytes: Int = maxInspectorBytes) -> String {
        guard !data.isEmpty else { return "" }
        if looksLikeGzip(data) {
            return "Response is gzip-compressed (\(data.count) bytes). Switch to Hex or ensure capture decoded the body."
        }
        let slice = data.prefix(maxBytes)
        var text = String(decoding: slice, as: UTF8.self)
        if data.count > maxBytes {
            text += "\n\n… truncated (\(data.count) bytes total) …"
        }
        return text
    }

    static func looksLikeGzip(_ data: Data) -> Bool {
        data.count >= 2 && data[data.startIndex] == 0x1F && data[data.startIndex + 1] == 0x8B
    }

    static func prettyJSONIfValid(_ data: Data) -> String? {
        let trimmed = trimmedForJSONProbe(data)
        guard let obj = try? JSONSerialization.jsonObject(with: trimmed),
              let out = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])
        else { return nil }
        return String(decoding: out, as: UTF8.self)
    }

    static func jsonModeDisplay(_ data: Data) -> String {
        if looksLikeGzip(data) { return displayText(data) }
        let capped = Data(data.prefix(maxInspectorBytes))
        if let pretty = prettyJSONIfValid(capped) { return pretty }
        let raw = displayText(capped)
        return "Not valid JSON. Switch to Text or Hex.\n\n---\n\n\(raw.prefix(800))"
    }

    static func looksLikeHTML(_ data: Data, mime: String?) -> Bool {
        if let mime, mime.contains("html") { return true }
        let prefix = utf8Text(data).trimmingCharacters(in: .whitespacesAndNewlines).prefix(256).lowercased()
        return prefix.contains("<!doctype html") || prefix.contains("<html")
    }

    static func hexDump(_ data: Data, maxBytes: Int = 4096) -> String {
        let slice = data.prefix(maxBytes)
        return slice.map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}

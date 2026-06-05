//
//  SessionDiffTool.swift
//  ShubhranshProxy — Features (Phase 3)
//  Created by Shubhransh Gupta
//

import Foundation

enum SessionDiffTool {
    struct DiffLine: Identifiable, Sendable {
        var id: String { "\(kind)-\(text)" }
        var kind: Kind
        var text: String

        enum Kind: Sendable {
            case same, added, removed
        }
    }

    struct SessionDiff: Sendable {
        var requestHeaders: [DiffLine]
        var responseHeaders: [DiffLine]
        var requestBody: [DiffLine]
        var responseBody: [DiffLine]
        var overview: [(label: String, left: String, right: String, changed: Bool)]
    }

    static func compare(_ left: ProxySession, _ right: ProxySession) -> SessionDiff {
        SessionDiff(
            requestHeaders: diffLines(left: left.requestHeaders, right: right.requestHeaders),
            responseHeaders: diffLines(left: left.responseHeaders, right: right.responseHeaders),
            requestBody: diffBody(left: left.requestBody, right: right.requestBody),
            responseBody: diffBody(left: left.responseBody ?? Data(), right: right.responseBody ?? Data()),
            overview: overviewDiff(left: left, right: right)
        )
    }

    static func diffHeaders(_ left: String?, _ right: String?) -> [DiffLine] {
        diffLines(left: left, right: right)
    }

    private static func diffLines(left: String?, right: String?) -> [DiffLine] {
        let a = (left ?? "").split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let b = (right ?? "").split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var out: [DiffLine] = []
        let maxCount = max(a.count, b.count)
        for i in 0..<maxCount {
            let l = i < a.count ? a[i] : nil
            let r = i < b.count ? b[i] : nil
            if l == r, let l {
                out.append(.init(kind: .same, text: l))
            } else {
                if let l { out.append(.init(kind: .removed, text: l)) }
                if let r { out.append(.init(kind: .added, text: r)) }
            }
        }
        return out
    }

    private static func diffBody(left: Data, right: Data) -> [DiffLine] {
        let lText = BodyFormatting.utf8Text(left)
        let rText = BodyFormatting.utf8Text(right)
        if lText == rText {
            return lText.isEmpty ? [] : lText.split(separator: "\n", omittingEmptySubsequences: false).map {
                DiffLine(kind: .same, text: String($0))
            }
        }
        return diffLines(left: lText, right: rText)
    }

    private static func overviewDiff(left: ProxySession, right: ProxySession) -> [(String, String, String, Bool)] {
        [
            ("Method", left.method, right.method, left.method != right.method),
            ("URL", left.url, right.url, left.url != right.url),
            ("Status", left.statusLabel, right.statusLabel, left.statusLabel != right.statusLabel),
            ("Request size", byteLabel(left.requestSize), byteLabel(right.requestSize), left.requestSize != right.requestSize),
            ("Response size", byteLabel(left.responseSize ?? 0), byteLabel(right.responseSize ?? 0), left.responseSize != right.responseSize),
            ("Duration", durationLabel(left.durationMs), durationLabel(right.durationMs), left.durationMs != right.durationMs),
        ]
    }

    private static func byteLabel(_ n: Int) -> String {
        if n < 1024 { return "\(n) B" }
        return String(format: "%.1f KB", Double(n) / 1024)
    }

    private static func durationLabel(_ ms: Double?) -> String {
        guard let ms else { return "—" }
        return String(format: "%.0f ms", ms)
    }
}

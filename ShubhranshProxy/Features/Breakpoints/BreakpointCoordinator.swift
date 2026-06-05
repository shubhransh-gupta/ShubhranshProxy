//
//  BreakpointCoordinator.swift — Phase 4
//
//  Created by Shubhransh Gupta

import Foundation

@MainActor
@Observable
final class BreakpointCoordinator {
    var settings = BreakpointSnapshot()
    var pending: [PendingBreakpoint] = []
    var editedHeaders = ""
    var editedBody = ""
    var selectedPendingId: UUID?

    private var mailbox: BreakpointMailbox?

    func attach(mailbox: BreakpointMailbox) {
        self.mailbox = mailbox
    }

    var pendingCount: Int { pending.count }

    var status: String {
        if !settings.isEnabled { return "Breakpoints off — enable to pause matching requests/responses." }
        if pending.isEmpty { return "Breakpoints armed — matching traffic will pause here." }
        return "\(pending.count) breakpoint(s) waiting for your action."
    }

    func queue(_ item: PendingBreakpoint) {
        pending.append(item)
        selectedPendingId = item.id
        editedHeaders = item.headers
        editedBody = String(data: item.body, encoding: .utf8) ?? ""
    }

    func forwardSelected() {
        guard let id = selectedPendingId, let item = pending.first(where: { $0.id == id }) else { return }
        let rebuilt = rebuildRaw(from: item, headers: editedHeaders, bodyText: editedBody)
        resume(id: id, decision: BreakpointDecision(action: .forward, modifiedData: rebuilt))
    }

    func dropSelected() {
        guard let id = selectedPendingId else { return }
        resume(id: id, decision: BreakpointDecision(action: .drop, modifiedData: nil))
    }

    func forwardAllAutomatic() {
        while let first = pending.first {
            resume(id: first.id, decision: BreakpointDecision(action: .forward, modifiedData: first.rawData))
        }
    }

    func cancelAll() {
        mailbox?.cancelAll()
        pending.removeAll()
        selectedPendingId = nil
    }

    private func resume(id: UUID, decision: BreakpointDecision) {
        mailbox?.resume(id: id, decision: decision)
        pending.removeAll { $0.id == id }
        selectedPendingId = pending.first?.id
        if let next = pending.first {
            editedHeaders = next.headers
            editedBody = String(data: next.body, encoding: .utf8) ?? ""
        }
    }

    private func rebuildRaw(from item: PendingBreakpoint, headers: String, bodyText: String) -> Data {
        switch item.phase {
        case .request:
            let body = Data(bodyText.utf8)
            var lines = headers.split(separator: "\r\n", omittingEmptySubsequences: false).map(String.init)
            if lines.isEmpty { return item.rawData }
            if !lines[0].contains(" HTTP/") {
                lines[0] = "\(item.method) \(URL(string: item.url)?.path ?? "/") HTTP/1.1"
            }
            var foundLength = false
            for i in 1..<lines.count {
                if lines[i].isEmpty { break }
                if lines[i].lowercased().hasPrefix("content-length:") {
                    lines[i] = "Content-Length: \(body.count)"
                    foundLength = true
                }
            }
            if !foundLength {
                if let emptyIndex = lines.firstIndex(where: { $0.isEmpty }) {
                    lines.insert("Content-Length: \(body.count)", at: emptyIndex)
                } else {
                    lines.append("Content-Length: \(body.count)")
                    lines.append("")
                    lines.append("")
                }
            }
            let headerBlock = lines.joined(separator: "\r\n")
            let normalized = headerBlock.hasSuffix("\r\n\r\n") ? headerBlock : headerBlock + "\r\n\r\n"
            return Data(normalized.utf8) + body
        case .response:
            if headers.isEmpty { return item.rawData }
            let body = Data(bodyText.utf8)
            var block = headers
            if !block.hasSuffix("\r\n\r\n") { block += "\r\n\r\n" }
            return Data(block.utf8) + body
        }
    }
}

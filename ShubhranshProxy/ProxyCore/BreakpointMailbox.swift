//
//  BreakpointMailbox.swift — Phase 4
//
//  Created by Shubhransh Gupta

import Foundation

/// Thread-safe breakpoint gate callable from NIO worker threads.
final class BreakpointMailbox: @unchecked Sendable {
    private let lock = NSLock()
    private var settings = BreakpointSnapshot()
    private var waiters: [UUID: (BreakpointDecision) -> Void] = [:]

    func replace(_ snapshot: BreakpointSnapshot) {
        lock.lock()
        settings = snapshot
        lock.unlock()
    }

    func currentSettings() -> BreakpointSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return settings
    }

    func shouldBreak(phase: BreakpointPhase, url: String) -> Bool {
        lock.lock()
        let s = settings
        lock.unlock()
        guard s.isEnabled else { return false }
        switch phase {
        case .request: guard s.breakOnRequest else { return false }
        case .response: guard s.breakOnResponse else { return false }
        }
        return urlMatches(url, pattern: s.urlPattern)
    }

    /// Blocks the calling thread until the UI resumes this breakpoint.
    func awaitDecision(
        pending: PendingBreakpoint,
        onQueued: @Sendable @escaping (PendingBreakpoint) -> Void
    ) -> BreakpointDecision {
        let semaphore = DispatchSemaphore(value: 0)
        var decision = BreakpointDecision(action: .forward, modifiedData: nil)

        onQueued(pending)

        lock.lock()
        waiters[pending.id] = { result in
            decision = result
            semaphore.signal()
        }
        lock.unlock()

        semaphore.wait()
        return decision
    }

    func resume(id: UUID, decision: BreakpointDecision) {
        lock.lock()
        let waiter = waiters.removeValue(forKey: id)
        lock.unlock()
        waiter?(decision)
    }

    func cancelAll() {
        lock.lock()
        let all = waiters
        waiters.removeAll()
        lock.unlock()
        for (_, waiter) in all {
            waiter(BreakpointDecision(action: .drop, modifiedData: nil))
        }
    }

    var pendingCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return waiters.count
    }

    private func urlMatches(_ url: String, pattern: String) -> Bool {
        guard !pattern.isEmpty else { return true }
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return false }
        let range = NSRange(url.startIndex..<url.endIndex, in: url)
        return regex.firstMatch(in: url, options: [], range: range) != nil
    }
}

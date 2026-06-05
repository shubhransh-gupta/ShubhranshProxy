//
//  FeatureRegistry.swift
//  ShubhranshProxy — Feature flags & Phase 2–5 stubs
//  Created by Shubhransh Gupta
//

import Foundation

@MainActor
@Observable
final class FeatureRegistry {
    var breakpointsEnabled = false
    var rewriteEnabled = false
    var throttlingEnabled = false
    var blockListEnabled = false

    let breakpoints = BreakpointCoordinator()
    let rewrite = RewriteEngine()
    let throttling = ThrottleProfileStore()
    let blockList = BlockListStore()
    let composer = RequestComposer()
    let favorites = FavoritesStore()
}

enum ProductPhase: String, Sendable {
    case phase1 = "Phase 1 — HTTP capture, UI, SQLite"
    case phase2 = "Phase 2 — HTTPS MITM, cert trust"
    case phase3 = "Phase 3 — Full inspector, HAR, domains"
    case phase4 = "Phase 4 — Breakpoints, rewrite, throttle"
    case phase5 = "Phase 5 — HTTP/2, WebSocket, gRPC, scale"
}

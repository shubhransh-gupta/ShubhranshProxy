//
//  BreakpointModels.swift — Phase 4
//
//  Created by Shubhransh Gupta

import Foundation

struct BreakpointSnapshot: Sendable, Equatable, Codable {
    var isEnabled = false
    var breakOnRequest = true
    var breakOnResponse = false
    var urlPattern = ".*"
}

enum BreakpointPhase: String, Sendable, Codable {
    case request
    case response
}

struct BreakpointDecision: Sendable {
    enum Action: Sendable {
        case forward
        case drop
    }

    var action: Action
    var modifiedData: Data?
}

struct PendingBreakpoint: Identifiable, Sendable, Equatable {
    var id: UUID
    var phase: BreakpointPhase
    var method: String
    var url: String
    var host: String
    var headers: String
    var body: Data
    var rawData: Data
}

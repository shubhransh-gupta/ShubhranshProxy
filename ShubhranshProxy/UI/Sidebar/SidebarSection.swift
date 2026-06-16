//
//  SidebarSection.swift
//  ShubhranshProxy — Proxyman-style sidebar sections
//

import Foundation

enum SidebarSection: String, CaseIterable, Identifiable, Hashable {
    case domains = "Domains"
    case devices = "Devices"
    case pinned = "Pinned"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .domains: "globe"
        case .devices: "ipad.and.iphone"
        case .pinned: "star.fill"
        }
    }

    var helpText: String {
        switch self {
        case .domains: "Browse traffic grouped by domain"
        case .devices: "Browse traffic grouped by device"
        case .pinned: "Pinned domains and endpoints"
        }
    }

    private static let defaultsKey = "ShubhranshProxy.sidebar.activeSection"

    static func loadPersisted() -> SidebarSection {
        guard let raw = UserDefaults.standard.string(forKey: defaultsKey),
              let section = SidebarSection(rawValue: raw) else {
            return .domains
        }
        return section
    }

    func persist() {
        UserDefaults.standard.set(rawValue, forKey: Self.defaultsKey)
    }
}

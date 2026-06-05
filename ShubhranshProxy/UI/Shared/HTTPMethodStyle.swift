//
//  HTTPMethodStyle.swift
//  ShubhranshProxy — UI
//
//  Created by Shubhransh Gupta
//

import SwiftUI

enum HTTPMethodStyle {
    static func color(for method: String) -> Color {
        switch method.uppercased() {
        case "GET": return .blue
        case "POST": return .green
        case "PUT": return .orange
        case "PATCH": return .yellow
        case "DELETE": return .red
        case "HEAD": return .cyan
        case "OPTIONS": return .purple
        case "CONNECT": return .indigo
        case "TLS": return .pink
        case "DEVICE": return .mint
        default: return .secondary
        }
    }

    static func badge(_ method: String) -> some View {
        Text(method.uppercased())
            .font(.caption.bold().monospaced())
            .foregroundStyle(color(for: method))
    }
}

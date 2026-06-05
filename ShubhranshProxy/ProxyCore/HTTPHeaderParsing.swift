//
//  HTTPHeaderParsing.swift
//  ShubhranshProxy
//  Created by Shubhransh Gupta
//

import Foundation

enum HTTPHeaderParsing {
    static func contentType(from headerBlock: String?) -> String? {
        guard let headerBlock else { return nil }
        for line in headerBlock.split(separator: "\r\n") {
            let lower = line.lowercased()
            if lower.hasPrefix("content-type:") {
                return line.split(separator: ":", maxSplits: 1).last?
                    .trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    static func cookies(from headerBlock: String?) -> [(name: String, value: String)] {
        guard let headerBlock else { return [] }
        var out: [(String, String)] = []
        for line in headerBlock.split(separator: "\r\n") {
            if line.lowercased().hasPrefix("set-cookie:") || line.lowercased().hasPrefix("cookie:") {
                let value = line.split(separator: ":", maxSplits: 1).last.map(String.init) ?? ""
                let first = value.split(separator: ";").first.map(String.init) ?? value
                let parts = first.split(separator: "=", maxSplits: 1)
                if parts.count == 2 {
                    out.append((String(parts[0]), String(parts[1])))
                }
            }
        }
        return out
    }

    static func queryItems(from urlString: String) -> [(String, String)] {
        guard let url = URL(string: urlString),
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        else { return [] }
        return items.compactMap { item in
            guard let v = item.value else { return nil }
            return (item.name, v)
        }
    }
}

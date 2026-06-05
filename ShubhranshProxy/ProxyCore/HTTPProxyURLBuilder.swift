//
//  HTTPProxyURLBuilder.swift
//  ShubhranshProxy — ProxyCore
//  Created by Shubhransh Gupta
//
//  Builds a canonical URL string for logging, filters, and Map Local matching.
//

import Foundation

enum HTTPProxyURLBuilder {
    /// Full URL for proxy requests (absolute-form or origin-form + Host).
    static func fullURL(
        request: ParsedInboundRequest,
        host: String,
        port: Int,
        scheme: String = "http",
        defaultPort: Int = 80
    ) -> String {
        if request.isConnect {
            return "https://\(request.target)"
        }
        if let u = URL(string: request.target), u.scheme != nil, u.host != nil {
            return u.absoluteString
        }
        let path = request.target
        let authority = hostPortAuthority(host: host, port: port, schemeDefaultPort: defaultPort)
        if path.hasPrefix("/") || path == "*" {
            return "\(scheme)://\(authority)\(path == "*" ? path : path)"
        }
        return "\(scheme)://\(authority)/\(path)"
    }

    private static func hostPortAuthority(host: String, port: Int, schemeDefaultPort: Int) -> String {
        if host.contains(":") && !host.hasPrefix("[") {
            return "\(host):\(port)"
        }
        if port != schemeDefaultPort {
            if host.contains(":") { return "[\(host)]:\(port)" }
            return "\(host):\(port)"
        }
        return host
    }
}

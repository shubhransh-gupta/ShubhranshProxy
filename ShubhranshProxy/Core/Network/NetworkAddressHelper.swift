//
//  NetworkAddressHelper.swift
//  ShubhranshProxy — Core
//
//  Created by Shubhransh Gupta
//

import Foundation

enum NetworkAddressHelper {
    struct InterfaceAddress: Identifiable, Sendable, Equatable {
        var id: String { name }
        var name: String
        var address: String
    }

    /// Best-effort LAN IPv4 for physical iOS/Android devices on the same Wi‑Fi as this Mac.
    static func primaryIPv4Address() -> String? {
        allIPv4Addresses().first?.address
    }

    /// All active non-loopback IPv4 addresses — iPhone proxy must target one on the same LAN.
    static func allIPv4Addresses() -> [InterfaceAddress] {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return [] }
        defer { freeifaddrs(ifaddr) }

        var results: [InterfaceAddress] = []
        var pointer = first

        while true {
            let interface = pointer.pointee
            let flags = interface.ifa_flags
            let isUp = (flags & UInt32(IFF_UP)) != 0
            let isLoopback = (flags & UInt32(IFF_LOOPBACK)) != 0

            if isUp, !isLoopback,
               let addr = interface.ifa_addr,
               addr.pointee.sa_family == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                let result = getnameinfo(
                    addr,
                    socklen_t(addr.pointee.sa_len),
                    &hostname,
                    socklen_t(hostname.count),
                    nil,
                    0,
                    NI_NUMERICHOST
                )
                if result == 0 {
                    let ip = String(cString: hostname)
                    if ClientAddressResolver.isPrivateLAN(ip) {
                        results.append(InterfaceAddress(name: name, address: ip))
                    }
                }
            }

            guard let next = interface.ifa_next else { break }
            pointer = next
        }

        return results.sorted { lhs, rhs in
            if lhs.name == "en0" { return true }
            if rhs.name == "en0" { return false }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }
}

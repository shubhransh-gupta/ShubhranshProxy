//
//  SystemProxyManager.swift
//  ShubhranshProxy — Core
//  Created by Shubhransh Gupta
//
//  Enables macOS HTTP/HTTPS system proxy while capture is running and restores prior settings on stop.
//

import Foundation

enum SystemProxyManager {
    struct ServiceProxySnapshot: Codable, Equatable, Sendable {
        var serviceName: String
        var webEnabled: Bool
        var webHost: String
        var webPort: Int
        var secureEnabled: Bool
        var secureHost: String
        var securePort: Int
    }

    struct VerificationResult: Sendable, Equatable {
        var activeService: String
        var expectedHost: String
        var expectedPort: Int
        var actualHost: String
        var actualPort: Int
        var isCorrect: Bool
    }

    enum SystemProxyError: Error, LocalizedError {
        case noNetworkService
        case commandFailed(String)
        case authorizationCancelled
        case verificationFailed(VerificationResult)

        var errorDescription: String? {
            switch self {
            case .noNetworkService:
                return "No active network service found. Configure a browser proxy manually in Setup."
            case .authorizationCancelled:
                return SystemCommandRunner.CommandError.authorizationCancelled.errorDescription
            case .commandFailed(let message):
                return message
            case .verificationFailed(let result):
                return """
                macOS is still routing traffic through \(result.actualHost):\(result.actualPort) on “\(result.activeService)”, \
                but ShubhranshProxy is listening on \(result.expectedHost):\(result.expectedPort). \
                Stop other proxies (e.g. Proxyman on 9090), then press Stop and Start again.
                """
            }
        }
    }

    private static let snapshotsDefaultsKey = "ShubhranshProxy.systemProxySnapshots"
    private static var appliedSnapshots: [ServiceProxySnapshot] = []

    /// Returns true when the active network interface is already routed through this listener (no admin needed).
    static func isAlreadyConfigured(host: String, port: Int) -> Bool {
        verifySystemProxy(host: host, port: port).isCorrect
    }

    /// Whether macOS Wi‑Fi/Ethernet is still pointing at this app's listener.
    static func isRoutingThroughApp(host: String, port: Int) -> Bool {
        isAlreadyConfigured(host: host, port: port)
    }

    private static func serviceMatches(host: String, port: Int, service: String) -> Bool {
        guard let snap = try? readProxySettings(for: service) else { return false }
        return snap.webEnabled
            && snap.secureEnabled
            && snap.webPort == port
            && snap.securePort == port
            && hostsMatch(snap.webHost, host)
            && hostsMatch(snap.secureHost, host)
    }

    /// Routes proxy-aware macOS apps through the local listener on every enabled network service.
    /// Skips the admin password when settings are already correct (Charles/Proxyman-style).
    static func enable(host: String, port: Int) throws {
        if isAlreadyConfigured(host: host, port: port) {
            return
        }

        // Active interface already correct — skip privileged writes to other adapters.
        if verifySystemProxy(host: host, port: port).isCorrect {
            return
        }

        let services = try targetNetworkServices()
        guard !services.isEmpty else { throw SystemProxyError.noNetworkService }

        var snapshots: [ServiceProxySnapshot] = []
        var commands: [[String]] = []
        for service in services where !serviceMatches(host: host, port: port, service: service) {
            snapshots.append(try readProxySettings(for: service))
            commands.append(contentsOf: setProxyCommands(for: service, host: host, port: port, enabled: true))
        }
        if commands.isEmpty {
            let verification = verifySystemProxy(host: host, port: port)
            guard verification.isCorrect else {
                throw SystemProxyError.verificationFailed(verification)
            }
            return
        }
        try applyNetworkSetupCommands(commands)

        appliedSnapshots = snapshots
        persistSnapshots(snapshots)

        try ensureProxyRoutingVerified(host: host, port: port, services: services)
    }

    /// Confirms proxy is enabled; retries state-only commands when host/port were set but left disabled.
    private static func ensureProxyRoutingVerified(host: String, port: Int, services: [String]) throws {
        var verification = verifySystemProxy(host: host, port: port)
        if verification.isCorrect { return }

        let stateCommands = services.flatMap { service -> [[String]] in
            guard !serviceMatches(host: host, port: port, service: service) else { return [] }
            return [
                ["-setwebproxystate", service, "on"],
                ["-setsecurewebproxystate", service, "on"],
            ]
        }
        if !stateCommands.isEmpty {
            try applyNetworkSetupCommands(stateCommands)
            verification = verifySystemProxy(host: host, port: port)
        }

        guard verification.isCorrect else {
            throw SystemProxyError.verificationFailed(verification)
        }
    }

    /// Applies networksetup without admin when macOS allows it; escalates only if that fails.
    private static func applyNetworkSetupCommands(_ commandGroups: [[String]]) throws {
        guard !commandGroups.isEmpty else { return }
        if runNetworkSetupBatch(commandGroups) {
            return
        }
        try runNetworkSetupPrivileged(commandGroups)
    }

    @discardableResult
    private static func runNetworkSetupBatch(_ commandGroups: [[String]]) -> Bool {
        for group in commandGroups {
            do {
                _ = try runNetworkSetup(group)
            } catch {
                return false
            }
        }
        return true
    }

    /// Restores saved proxy settings, or turns off the proxy on Wi‑Fi/Ethernet when still routed here.
    static func disable(restore: Bool, fallbackHost: String? = nil, fallbackPort: Int? = nil) throws {
        guard restore else { return }

        let snapshots = appliedSnapshots.isEmpty ? loadPersistedSnapshots() : appliedSnapshots
        if !snapshots.isEmpty {
            let commands = snapshots.flatMap(restoreProxyCommands)
            try applyNetworkSetupCommands(commands)
            appliedSnapshots = []
            clearPersistedSnapshots()
            return
        }

        guard let fallbackHost, let fallbackPort else { return }
        guard isAlreadyConfigured(host: fallbackHost, port: fallbackPort) else { return }

        let services = try targetNetworkServices()
        let commands = services.flatMap(turnOffProxyCommands)
        try applyNetworkSetupCommands(commands)
    }

    /// True when a previous enable saved pre-proxy settings that still need restoring.
    static func hasPersistedRestoreSnapshots() -> Bool {
        !loadPersistedSnapshots().isEmpty
    }

    private static func hostsMatch(_ lhs: String, _ rhs: String) -> Bool {
        if lhs == rhs { return true }
        let left = lhs.lowercased()
        let right = rhs.lowercased()
        return (left == "localhost" && right == "127.0.0.1")
            || (left == "127.0.0.1" && right == "localhost")
    }

    static func verifySystemProxy(host: String, port: Int) -> VerificationResult {
        let active = activeNetworkServiceName() ?? "Wi-Fi"
        let snapshot = try? readProxySettings(for: active)
        let webHost = snapshot?.webHost ?? ""
        let webPort = snapshot?.webPort ?? 0
        let webEnabled = snapshot?.webEnabled ?? false
        let secureEnabled = snapshot?.secureEnabled ?? false
        let secureHost = snapshot?.secureHost ?? ""
        let securePort = snapshot?.securePort ?? 0

        let webOK = webEnabled && hostsMatch(webHost, host) && webPort == port
        let secureOK = secureEnabled && hostsMatch(secureHost, host) && securePort == port
        let isCorrect = webOK && secureOK

        let actualHost = webEnabled ? webHost : secureHost
        let actualPort = webEnabled ? webPort : securePort

        return VerificationResult(
            activeService: active,
            expectedHost: host,
            expectedPort: port,
            actualHost: actualHost,
            actualPort: actualPort,
            isCorrect: isCorrect
        )
    }

    // MARK: - Private

    /// Interface carrying traffic right now (e.g. en0 → Wi-Fi).
    private static func activeNetworkServiceName() -> String? {
        guard let device = activeNetworkDeviceName() else { return nil }
        return hardwarePortName(for: device)
    }

    private static func activeNetworkDeviceName() -> String? {
        guard let scutil = try? SystemCommandRunner.executableURL(named: "scutil") else { return nil }
        let output = (try? SystemCommandRunner.run(scutil, arguments: ["--nwi"])) ?? ""
        for line in output.split(separator: "\n") {
            let trimmed = String(line).trimmingCharacters(in: .whitespaces)
            guard trimmed.first?.isNumber == true || trimmed.hasPrefix("en") else { continue }
            let parts = trimmed.split(separator: ":")
            guard parts.count >= 2 else { continue }
            let device = String(parts[0]).trimmingCharacters(in: .whitespaces)
            if device.hasPrefix("en") { return device }
        }
        if let interfacesLine = output.split(separator: "\n").first(where: { $0.hasPrefix("Network interfaces:") }) {
            let list = interfacesLine.replacingOccurrences(of: "Network interfaces:", with: "")
                .trimmingCharacters(in: .whitespaces)
            if let first = list.split(separator: " ").first {
                return String(first)
            }
        }
        return nil
    }

    private static func hardwarePortName(for device: String) -> String? {
        guard let orderOutput = try? runNetworkSetup(["-listallhardwareports"]) else { return nil }
        var currentPort: String?
        for line in orderOutput.split(separator: "\n") {
            let trimmed = String(line).trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("Hardware Port:") {
                currentPort = trimmed.replacingOccurrences(of: "Hardware Port:", with: "")
                    .trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("Device:") {
                let dev = trimmed.replacingOccurrences(of: "Device:", with: "")
                    .trimmingCharacters(in: .whitespaces)
                if dev == device { return currentPort }
            }
        }
        return nil
    }

    private static func enabledNetworkServices() throws -> [String] {
        let output = try runNetworkSetup(["-listallnetworkservices"])
        return output
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { !$0.hasPrefix("*") }
            .filter { !$0.localizedCaseInsensitiveContains("asterisk") }
    }

    /// Services that actually carry user traffic (active interface + Wi‑Fi), not every virtual adapter.
    private static func targetNetworkServices() throws -> [String] {
        let all = try enabledNetworkServices()
        guard !all.isEmpty else { return [] }

        var targets: [String] = []
        if let active = activeNetworkServiceName(), all.contains(active) {
            targets.append(active)
        }
        if all.contains("Wi-Fi"), !targets.contains("Wi-Fi") {
            targets.append("Wi-Fi")
        }
        if targets.isEmpty {
            targets.append(all[0])
        }
        return targets
    }

    private static func readProxySettings(for service: String) throws -> ServiceProxySnapshot {
        let web = parseProxyBlock(try runNetworkSetup(["-getwebproxy", service]))
        let secure = parseProxyBlock(try runNetworkSetup(["-getsecurewebproxy", service]))
        return ServiceProxySnapshot(
            serviceName: service,
            webEnabled: web.enabled,
            webHost: web.host,
            webPort: web.port,
            secureEnabled: secure.enabled,
            secureHost: secure.host,
            securePort: secure.port
        )
    }

    private static func setProxyCommands(for service: String, host: String, port: Int, enabled: Bool) -> [[String]] {
        let state = enabled ? "on" : "off"
        let portString = String(port)
        return [
            ["-setwebproxy", service, host, portString],
            ["-setsecurewebproxy", service, host, portString],
            ["-setwebproxystate", service, state],
            ["-setsecurewebproxystate", service, state],
        ]
    }

    private static func restoreProxyCommands(for snapshot: ServiceProxySnapshot) -> [[String]] {
        let webState = snapshot.webEnabled ? "on" : "off"
        let secureState = snapshot.secureEnabled ? "on" : "off"
        return [
            ["-setwebproxy", snapshot.serviceName, snapshot.webHost, String(snapshot.webPort)],
            ["-setsecurewebproxy", snapshot.serviceName, snapshot.secureHost, String(snapshot.securePort)],
            ["-setwebproxystate", snapshot.serviceName, webState],
            ["-setsecurewebproxystate", snapshot.serviceName, secureState],
        ]
    }

    private static func turnOffProxyCommands(for service: String) -> [[String]] {
        [
            ["-setwebproxystate", service, "off"],
            ["-setsecurewebproxystate", service, "off"],
        ]
    }

    private struct ParsedProxy {
        var enabled = false
        var host = ""
        var port = 0
    }

    private static func parseProxyBlock(_ output: String) -> ParsedProxy {
        var parsed = ParsedProxy()
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: ":", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard parts.count == 2 else { continue }
            switch parts[0].lowercased() {
            case "enabled":
                parsed.enabled = parts[1].lowercased() == "yes"
            case "server":
                parsed.host = parts[1]
            case "port":
                parsed.port = Int(parts[1]) ?? 0
            default:
                break
            }
        }
        return parsed
    }

    private static func networkSetupExecutableURL() throws -> URL {
        try SystemCommandRunner.executableURL(named: "networksetup")
    }

    @discardableResult
    private static func runNetworkSetup(_ arguments: [String]) throws -> String {
        do {
            return try SystemCommandRunner.run(try networkSetupExecutableURL(), arguments: arguments)
        } catch let error as SystemCommandRunner.CommandError {
            throw mapCommandError(error)
        }
    }

    private static func runNetworkSetupPrivileged(_ commandGroups: [[String]]) throws {
        guard !commandGroups.isEmpty else { return }
        let networkSetup = try networkSetupExecutableURL().path
        let shell = commandGroups
            .map { args in
                ([networkSetup] + args)
                    .map(SystemCommandRunner.shellSingleQuote)
                    .joined(separator: " ")
            }
            .joined(separator: " && ")
        do {
            try SystemCommandRunner.runPrivilegedShell(shell)
        } catch let error as SystemCommandRunner.CommandError {
            throw mapCommandError(error)
        }
    }

    private static func mapCommandError(_ error: SystemCommandRunner.CommandError) -> SystemProxyError {
        switch error {
        case .authorizationCancelled:
            return .authorizationCancelled
        case .executableNotFound(let name):
            return .commandFailed(
                "Could not find \(name). Enable the proxy manually in System Settings → Network → Proxies."
            )
        case .failed(let message):
            return .commandFailed(message)
        }
    }

    private static func persistSnapshots(_ snapshots: [ServiceProxySnapshot]) {
        if let data = try? JSONEncoder().encode(snapshots) {
            UserDefaults.standard.set(data, forKey: snapshotsDefaultsKey)
        }
    }

    private static func loadPersistedSnapshots() -> [ServiceProxySnapshot] {
        guard let data = UserDefaults.standard.data(forKey: snapshotsDefaultsKey),
              let snapshots = try? JSONDecoder().decode([ServiceProxySnapshot].self, from: data) else {
            return []
        }
        return snapshots
    }

    private static func clearPersistedSnapshots() {
        UserDefaults.standard.removeObject(forKey: snapshotsDefaultsKey)
    }
}

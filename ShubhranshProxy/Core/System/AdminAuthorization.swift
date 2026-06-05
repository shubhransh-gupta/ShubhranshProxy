//
//  AdminAuthorization.swift
//  ShubhranshProxy — Core
//  Created by Shubhransh Gupta
//
//  Runs privileged shell commands only when macOS proxy must change.
//  Prompts once per app session; subsequent proxy changes reuse cached rights silently.
//

import Foundation
import Security

enum AdminAuthorization {
    private static let executeRight = "system.privilege.admin"
    private static var cachedRef: AuthorizationRef?
    /// True after the user has approved the admin prompt once this app session.
    private static var sessionAuthorized = false

    private static let authorizationPrompt =
        "ShubhranshProxy needs your password to update macOS Wi‑Fi/Ethernet proxy settings."

    /// Runs a shell command as root. Prompts at most once per app session when macOS proxy changes are needed.
    static func runPrivilegedShell(_ shellCommand: String) throws {
        try runViaAuthorizationServices(shellCommand)
    }

    private static func runViaAuthorizationServices(_ shellCommand: String) throws {
        try executePrivilegedShell(shellCommand)
    }

    private static func executePrivilegedShell(_ shellCommand: String) throws {
        let auth = try obtainAuthorizationRef()

        let outputCapacity = 16_384
        let outputBuffer = UnsafeMutablePointer<CChar>.allocate(capacity: outputCapacity)
        defer { outputBuffer.deallocate() }

        let status = shellCommand.withCString { commandPointer in
            SPXRunPrivilegedShell(
                auth,
                commandPointer,
                outputBuffer,
                outputCapacity,
                false
            )
        }

        if status == errAuthorizationDenied || status == errAuthorizationInteractionNotAllowed {
            invalidateCachedAuthorization()
            throw SystemCommandRunner.CommandError.failed(
                "Administrator authorization expired (OSStatus \(status))."
            )
        }

        guard status == errAuthorizationSuccess else {
            if status == errAuthorizationCanceled {
                throw SystemCommandRunner.CommandError.authorizationCancelled
            }
            let hint = authorizationErrorHint(for: status)
            throw SystemCommandRunner.CommandError.failed(
                "ShubhranshProxy could not obtain administrator access (OSStatus \(status)). \(hint)"
            )
        }

        let trimmed = String(cString: outputBuffer).trimmingCharacters(in: .whitespacesAndNewlines)
        if isUserCanceled(output: trimmed) {
            throw SystemCommandRunner.CommandError.authorizationCancelled
        }
        if trimmed.localizedCaseInsensitiveContains("authorization failed")
            || trimmed.localizedCaseInsensitiveContains("not authorized") {
            invalidateCachedAuthorization()
            throw SystemCommandRunner.CommandError.failed(
                trimmed.isEmpty ? "Administrator authorization was denied." : trimmed
            )
        }

        sessionAuthorized = true
    }

    private static func obtainAuthorizationRef() throws -> AuthorizationRef {
        if let cachedRef, ensureAdminRights(on: cachedRef, allowInteraction: false) {
            return cachedRef
        }

        // First approval, or rights expired — allow one interactive re-prompt this session.
        if let cachedRef, ensureAdminRights(on: cachedRef, allowInteraction: true) {
            sessionAuthorized = true
            return cachedRef
        }

        invalidateCachedAuthorization()

        var created: AuthorizationRef?
        let createStatus = withPromptEnvironment { environment in
            AuthorizationCreate(nil, environment, [], &created)
        }
        guard createStatus == errAuthorizationSuccess, let created else {
            throw SystemCommandRunner.CommandError.failed("Could not create authorization reference.")
        }

        guard ensureAdminRights(on: created, allowInteraction: true) else {
            AuthorizationFree(created, [.destroyRights])
            throw SystemCommandRunner.CommandError.authorizationCancelled
        }

        cachedRef = created
        sessionAuthorized = true
        return created
    }

    @discardableResult
    private static func ensureAdminRights(on authorization: AuthorizationRef, allowInteraction: Bool) -> Bool {
        executeRight.withCString { rightName in
            var item = AuthorizationItem(name: rightName, valueLength: 0, value: nil, flags: 0)
            return withUnsafeMutablePointer(to: &item) { itemPointer in
                var rights = AuthorizationRights(count: 1, items: itemPointer)
                var rawFlags = AuthorizationFlags.extendRights.rawValue
                    | AuthorizationFlags.preAuthorize.rawValue
                if allowInteraction {
                    rawFlags |= AuthorizationFlags.interactionAllowed.rawValue
                    return withPromptEnvironment { environment in
                        AuthorizationCopyRights(authorization, &rights, environment, AuthorizationFlags(rawValue: rawFlags), nil)
                            == errAuthorizationSuccess
                    }
                }
                return AuthorizationCopyRights(authorization, &rights, nil, AuthorizationFlags(rawValue: rawFlags), nil)
                    == errAuthorizationSuccess
            }
        }
    }

    private static func isUserCanceled(output: String) -> Bool {
        if output.contains("(-128)") { return true }
        let lowered = output.lowercased()
        return lowered.contains("user canceled") || lowered.contains("user cancelled")
    }

    /// Supplies `kAuthorizationEnvironmentPrompt` so macOS shows ShubhranshProxy instead of osascript.
    private static func withPromptEnvironment<T>(
        _ body: (UnsafeMutablePointer<AuthorizationEnvironment>?) throws -> T
    ) rethrows -> T {
        try authorizationPrompt.withCString { promptPointer in
            var promptItem = AuthorizationItem(
                name: kAuthorizationEnvironmentPrompt,
                valueLength: authorizationPrompt.utf8.count,
                value: UnsafeMutableRawPointer(mutating: promptPointer),
                flags: 0
            )
            return try withUnsafeMutablePointer(to: &promptItem) { itemPointer in
                var environment = AuthorizationEnvironment(count: 1, items: itemPointer)
                return try body(&environment)
            }
        }
    }

    private static func invalidateCachedAuthorization() {
        if let cachedRef {
            AuthorizationFree(cachedRef, [.destroyRights])
        }
        cachedRef = nil
        sessionAuthorized = false
    }

    private static func authorizationErrorHint(for status: OSStatus) -> String {
        if status == -60011 {
            return """
            Disable “Route macOS traffic” in Proxy settings and set 127.0.0.1:8888 manually in System Settings → Network → Proxies.
            """
        }
        return "Approve the ShubhranshProxy administrator password prompt when macOS asks."
    }
}

//
//  AdminAuthorization.swift
//  ShubhranshProxy — Core
//  Created by Shubhransh Gupta
//
//  Runs privileged shell commands when macOS proxy must change.
//  Tries Authorization Services first (ShubhranshProxy prompt), falls back to AppleScript if needed.
//

import Foundation
import Security

enum AdminAuthorization {
    private static let executeRight = "system.privilege.admin"
    private static var cachedRef: AuthorizationRef?
    private static var sessionAuthorized = false

    private static let authorizationPrompt =
        "ShubhranshProxy needs your password to update macOS Wi‑Fi/Ethernet proxy settings."

    static func runPrivilegedShell(_ shellCommand: String) throws {
        do {
            try runViaAuthorizationServices(shellCommand)
        } catch SystemCommandRunner.CommandError.authorizationCancelled {
            throw SystemCommandRunner.CommandError.authorizationCancelled
        } catch {
            try runViaAppleScript(shellCommand)
        }
    }

    // MARK: - Authorization Services

    private static func runViaAuthorizationServices(_ shellCommand: String) throws {
        let auth = try obtainAuthorizationRef()

        let outputCapacity = 16_384
        let outputBuffer = UnsafeMutablePointer<CChar>.allocate(capacity: outputCapacity)
        defer { outputBuffer.deallocate() }

        var finalStatus = shellCommand.withCString { commandPointer in
            SPXRunPrivilegedShell(
                auth,
                commandPointer,
                outputBuffer,
                outputCapacity,
                false
            )
        }

        if finalStatus == errAuthorizationDenied || finalStatus == errAuthorizationInteractionNotAllowed {
            finalStatus = shellCommand.withCString { commandPointer in
                SPXRunPrivilegedShell(
                    auth,
                    commandPointer,
                    outputBuffer,
                    outputCapacity,
                    true
                )
            }
            if finalStatus != errAuthorizationSuccess {
                invalidateCachedAuthorization()
                throw SystemCommandRunner.CommandError.failed(
                    "Administrator authorization expired (OSStatus \(finalStatus))."
                )
            }
        }

        guard finalStatus == errAuthorizationSuccess else {
            if finalStatus == errAuthorizationCanceled {
                throw SystemCommandRunner.CommandError.authorizationCancelled
            }
            throw SystemCommandRunner.CommandError.failed(
                "Authorization Services failed (OSStatus \(finalStatus))."
            )
        }

        try validateShellOutput(outputBuffer)
        sessionAuthorized = true
    }

    // MARK: - AppleScript fallback (reliable for networksetup on modern macOS)

    private static func runViaAppleScript(_ shellCommand: String) throws {
        let escaped = shellCommand
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = "do shell script \"\(escaped)\" with administrator privileges"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()

        let output = String(
            data: pipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard process.terminationStatus == 0 else {
            if isUserCanceled(output: output) {
                throw SystemCommandRunner.CommandError.authorizationCancelled
            }
            throw SystemCommandRunner.CommandError.failed(
                output.isEmpty ? "Administrator command failed." : output
            )
        }

        sessionAuthorized = true
    }

    private static func validateShellOutput(_ outputBuffer: UnsafeMutablePointer<CChar>) throws {
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
    }

    private static func obtainAuthorizationRef() throws -> AuthorizationRef {
        if let cachedRef, ensureAdminRights(on: cachedRef, allowInteraction: false) {
            return cachedRef
        }

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
}

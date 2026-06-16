//
//  AdminAuthorization.swift
//  ShubhranshProxy — Core
//
//  Runs privileged networksetup only when the non-privileged path fails.
//

import Foundation
import Security

enum AdminAuthorization {
    private static var cachedRef: AuthorizationRef?
    private static var sessionExecuteSucceeded = false
    private static var interactivePromptShownThisSession = false

    private static let authorizationPrompt =
        "ShubhranshProxy needs your password to update macOS Wi‑Fi/Ethernet proxy settings."

    static func runPrivilegedShell(_ shellCommand: String) throws {
        // Prefer AppleScript on modern macOS — AuthorizationExecuteWithPrivileges is deprecated and flaky.
        if !sessionExecuteSucceeded {
            do {
                try runViaAppleScript(shellCommand)
                return
            } catch SystemCommandRunner.CommandError.authorizationCancelled {
                throw SystemCommandRunner.CommandError.authorizationCancelled
            } catch {
                // Fall through to Authorization Services once.
            }
        }

        do {
            try runViaAuthorizationServices(shellCommand)
        } catch SystemCommandRunner.CommandError.authorizationCancelled {
            throw SystemCommandRunner.CommandError.authorizationCancelled
        } catch {
            if sessionExecuteSucceeded || interactivePromptShownThisSession {
                throw error
            }
            try runViaAppleScript(shellCommand)
        }
    }

    private static func runViaAuthorizationServices(_ shellCommand: String) throws {
        let auth = try getOrCreateAuthorizationRef()
        guard copyAdminRights(on: auth, allowInteraction: !sessionExecuteSucceeded) else {
            throw SystemCommandRunner.CommandError.authorizationCancelled
        }

        let outputCapacity = 16_384
        let outputBuffer = UnsafeMutablePointer<CChar>.allocate(capacity: outputCapacity)
        defer { outputBuffer.deallocate() }

        let status = executeShell(auth, shellCommand, outputBuffer, outputCapacity, false)
        if status == errAuthorizationSuccess {
            try validateShellOutput(outputBuffer)
            sessionExecuteSucceeded = true
            return
        }

        if status == errAuthorizationCanceled {
            throw SystemCommandRunner.CommandError.authorizationCancelled
        }

        invalidateCachedAuthorization()
        throw SystemCommandRunner.CommandError.failed(
            "Administrator authorization failed (OSStatus \(status))."
        )
    }

    private static func getOrCreateAuthorizationRef() throws -> AuthorizationRef {
        if let cachedRef { return cachedRef }
        var created: AuthorizationRef?
        let status = AuthorizationCreate(nil, nil, [], &created)
        guard status == errAuthorizationSuccess, let created else {
            throw SystemCommandRunner.CommandError.failed("Could not create authorization reference.")
        }
        cachedRef = created
        return created
    }

    @discardableResult
    private static func copyAdminRights(on authorization: AuthorizationRef, allowInteraction: Bool) -> Bool {
        "system.privilege.admin".withCString { rightName in
            var item = AuthorizationItem(name: rightName, valueLength: 0, value: nil, flags: 0)
            return withUnsafeMutablePointer(to: &item) { itemPointer in
                var rights = AuthorizationRights(count: 1, items: itemPointer)
                var rawFlags = AuthorizationFlags.extendRights.rawValue
                    | AuthorizationFlags.preAuthorize.rawValue
                if allowInteraction {
                    rawFlags |= AuthorizationFlags.interactionAllowed.rawValue
                    return withPromptEnvironment { environment in
                        AuthorizationCopyRights(
                            authorization,
                            &rights,
                            environment,
                            AuthorizationFlags(rawValue: rawFlags),
                            nil
                        ) == errAuthorizationSuccess
                    }
                }
                return AuthorizationCopyRights(
                    authorization,
                    &rights,
                    nil,
                    AuthorizationFlags(rawValue: rawFlags),
                    nil
                ) == errAuthorizationSuccess
            }
        }
    }

    private static func executeShell(
        _ auth: AuthorizationRef,
        _ shellCommand: String,
        _ outputBuffer: UnsafeMutablePointer<CChar>,
        _ outputCapacity: Int,
        _ allowInteraction: Bool
    ) -> OSStatus {
        shellCommand.withCString { commandPointer in
            SPXRunPrivilegedShell(
                auth,
                commandPointer,
                outputBuffer,
                outputCapacity,
                allowInteraction
            )
        }
    }

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

        interactivePromptShownThisSession = true
        sessionExecuteSucceeded = true
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
        sessionExecuteSucceeded = false
    }
}

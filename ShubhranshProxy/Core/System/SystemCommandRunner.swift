//
//  SystemCommandRunner.swift
//  ShubhranshProxy — Core
//  Created by Shubhransh Gupta
//
//  Safe helpers for running macOS CLI tools with full paths and optional admin elevation.
//

import Foundation

enum SystemCommandRunner {
    enum CommandError: Error, LocalizedError {
        case executableNotFound(String)
        case failed(String)
        case authorizationCancelled

        var errorDescription: String? {
            switch self {
            case .executableNotFound(let name):
                return "Required macOS tool not found: \(name)."
            case .authorizationCancelled:
                return """
                ShubhranshProxy needs your administrator password once to change macOS network proxy settings. \
                Approve the prompt, or disable “Route macOS traffic” and configure apps manually.
                """
            case .failed(let message):
                return message
            }
        }
    }

    static func executableURL(
        named name: String,
        searchPaths: [String] = ["/usr/sbin", "/usr/bin", "/sbin", "/bin"]
    ) throws -> URL {
        for directory in searchPaths {
            let path = (directory as NSString).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        throw CommandError.executableNotFound(name)
    }

    @discardableResult
    static func run(_ executable: URL, arguments: [String] = []) throws -> String {
        if Thread.isMainThread {
            return try runSubprocess(executable, arguments: arguments)
        }
        return try runSubprocessOnCurrentThread(executable, arguments: arguments)
    }

    private static func runSubprocess(_ executable: URL, arguments: [String]) throws -> String {
        try DispatchQueue.global(qos: .userInitiated).sync {
            try runSubprocessOnCurrentThread(executable, arguments: arguments)
        }
    }

    @discardableResult
    private static func runSubprocessOnCurrentThread(_ executable: URL, arguments: [String]) throws -> String {
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw CommandError.executableNotFound(executable.lastPathComponent)
        }

        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
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
            if isAuthorizationCancelled(output: output, status: process.terminationStatus) {
                throw CommandError.authorizationCancelled
            }
            let label = executable.lastPathComponent
            let message = output.isEmpty
                ? "\(label) \(arguments.joined(separator: " ")) failed."
                : output
            throw CommandError.failed(message)
        }
        return output
    }

    static func runPrivilegedShell(_ shellCommand: String) throws {
        try AdminAuthorization.runPrivilegedShell(shellCommand)
    }

    static func shellSingleQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }

    private static func isAuthorizationCancelled(output: String, status: Int32) -> Bool {
        if status == 1 && output.localizedCaseInsensitiveContains("user canceled") { return true }
        if output.contains("(-128)") { return true }
        if output.localizedCaseInsensitiveContains("canceled")
            && output.localizedCaseInsensitiveContains("authoriz") {
            return true
        }
        return false
    }
}

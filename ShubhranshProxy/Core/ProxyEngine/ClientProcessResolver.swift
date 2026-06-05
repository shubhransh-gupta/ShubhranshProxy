//
//  ClientProcessResolver.swift
//  ShubhranshProxy — ProxyCore
//  Created by Shubhransh Gupta
//
//  Maps an incoming proxy connection to the macOS process that opened it.
//

import Darwin
import Foundation
import NIOCore

enum ClientProcessResolver {
    static func appName(for channel: Channel) -> String? {
        guard let serverPort = channel.localAddress?.port,
              let clientPort = channel.remoteAddress?.port else { return nil }
        return appName(serverPort: serverPort, clientPort: clientPort)
    }

    private static func appName(serverPort: Int, clientPort: Int) -> String? {
        guard let lsof = try? SystemCommandRunner.executableURL(named: "lsof") else { return nil }
        let output = (try? SystemCommandRunner.run(
            lsof,
            arguments: ["-nP", "-iTCP:\(serverPort)", "-sTCP:ESTABLISHED"]
        )) ?? ""

        for line in output.split(separator: "\n").dropFirst() {
            let text = String(line)
            guard text.contains("->127.0.0.1:\(clientPort)")
                || text.contains("->[::1]:\(clientPort)") else { continue }
            let columns = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            guard columns.count >= 2, let pid = pid_t(columns[1]) else { continue }
            let name = processName(pid: pid)
            if SessionDisplayRules.isSelfProcess(name) { continue }
            return AppDomainCatalog.displayName(forProcessName: name)
        }
        return nil
    }

    private static func processName(pid: pid_t) -> String? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        let bytes = withUnsafeBytes(of: info.pbi_name) { Array($0) }
        return bytes.withUnsafeBufferPointer { buffer in
            buffer.baseAddress.map { String(cString: $0) }
        }
    }
}

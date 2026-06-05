//
//  SessionDatabase.swift
//  ShubhranshProxy — Persistence (SQLite)
//  Created by Shubhransh Gupta
//

import Foundation
import SQLite3

/// SQLite persistence for captured proxy sessions (Phase 1).
final class SessionDatabase: @unchecked Sendable {
    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "com.lk.ShubhranshProxy.sqlite", qos: .utility)

    init() throws {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("ShubhranshProxy", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("sessions.sqlite").path
        if sqlite3_open(path, &db) != SQLITE_OK {
            throw DatabaseError.openFailed(String(cString: sqlite3_errmsg(db)))
        }
        try exec("PRAGMA journal_mode=WAL;")
        try exec("""
        CREATE TABLE IF NOT EXISTS sessions (
            id TEXT PRIMARY KEY NOT NULL,
            started_at REAL NOT NULL,
            completed_at REAL,
            method TEXT NOT NULL,
            url TEXT NOT NULL,
            host TEXT NOT NULL,
            response_status INTEGER,
            duration_ms REAL,
            request_size INTEGER NOT NULL,
            response_size INTEGER,
            mime_type TEXT,
            request_headers TEXT NOT NULL,
            request_body BLOB NOT NULL,
            response_headers TEXT,
            response_body BLOB,
            error_message TEXT,
            was_mapped_local INTEGER NOT NULL,
            is_connect INTEGER NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_sessions_started ON sessions(started_at DESC);
        CREATE INDEX IF NOT EXISTS idx_sessions_host ON sessions(host);
        """)
    }

    deinit {
        if db != nil { sqlite3_close(db) }
    }

    func insert(_ session: ProxySession) throws {
        try queue.sync {
            let sql = """
            INSERT OR REPLACE INTO sessions VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?);
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw DatabaseError.prepareFailed(lastError)
            }
            defer { sqlite3_finalize(stmt) }
            let id = session.id.uuidString
            bindText(stmt, 1, id)
            sqlite3_bind_double(stmt, 2, session.startedAt)
            if let completed = session.completedAt {
                sqlite3_bind_double(stmt, 3, completed)
            } else {
                sqlite3_bind_null(stmt, 3)
            }
            bindText(stmt, 4, session.method)
            bindText(stmt, 5, session.url)
            bindText(stmt, 6, session.host)
            if let status = session.responseStatus {
                sqlite3_bind_int(stmt, 7, Int32(status))
            } else {
                sqlite3_bind_null(stmt, 7)
            }
            if let duration = session.durationMs {
                sqlite3_bind_double(stmt, 8, duration)
            } else {
                sqlite3_bind_null(stmt, 8)
            }
            sqlite3_bind_int(stmt, 9, Int32(session.requestSize))
            if let rs = session.responseSize {
                sqlite3_bind_int(stmt, 10, Int32(rs))
            } else {
                sqlite3_bind_null(stmt, 10)
            }
            if let mime = session.mimeType {
                bindText(stmt, 11, mime)
            } else {
                sqlite3_bind_null(stmt, 11)
            }
            bindText(stmt, 12, session.requestHeaders)
            _ = session.requestBody.withUnsafeBytes { ptr in
                sqlite3_bind_blob(stmt, 13, ptr.baseAddress, Int32(session.requestBody.count), SQLITE_TRANSIENT)
            }
            if let rh = session.responseHeaders {
                bindText(stmt, 14, rh)
            } else {
                sqlite3_bind_null(stmt, 14)
            }
            if let body = session.responseBody {
                _ = body.withUnsafeBytes { ptr in
                    sqlite3_bind_blob(stmt, 15, ptr.baseAddress, Int32(body.count), SQLITE_TRANSIENT)
                }
            } else {
                sqlite3_bind_null(stmt, 15)
            }
            if let err = session.errorMessage {
                bindText(stmt, 16, err)
            } else {
                sqlite3_bind_null(stmt, 16)
            }
            sqlite3_bind_int(stmt, 17, session.wasMappedLocal ? 1 : 0)
            sqlite3_bind_int(stmt, 18, session.isCONNECT ? 1 : 0)
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw DatabaseError.execFailed(lastError)
            }
        }
    }

    func deleteAll() throws {
        try exec("DELETE FROM sessions;")
    }

    private func exec(_ sql: String) throws {
        try queue.sync {
            if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
                throw DatabaseError.execFailed(lastError)
            }
        }
    }

    private var lastError: String {
        String(cString: sqlite3_errmsg(db))
    }

    private func bindText(_ stmt: OpaquePointer?, _ index: Int32, _ value: String) {
        _ = value.withCString { cstr in
            sqlite3_bind_text(stmt, index, cstr, -1, SQLITE_TRANSIENT)
        }
    }

    enum DatabaseError: Error, LocalizedError {
        case openFailed(String)
        case prepareFailed(String)
        case execFailed(String)
        var errorDescription: String? {
            switch self {
            case .openFailed(let m), .prepareFailed(let m), .execFailed(let m): return m
            }
        }
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

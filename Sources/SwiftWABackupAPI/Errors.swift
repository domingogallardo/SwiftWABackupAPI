//
//  Errors.swift
//  SwiftWABackupAPI
//
//  Created by Domingo Gallardo on 17/4/25.
//
//
//  Granular error namespaces that will eventually replace WABackupError.
//  While the migration is in progress we keep a compatibility layer.
//

import Foundation

// MARK: - Backup‑layer errors
public enum BackupError: Error, LocalizedError {
    case directoryAccess(Error)
    case invalidBackup(url: URL, reason: String)
    case fileCopy(source: URL, destination: URL, underlying: Error)

    public var errorDescription: String? {
        switch self {
        case .directoryAccess(let err):
            return "Failed to access backup directory: \(err.localizedDescription)"
        case .invalidBackup(let url, let reason):
            return "Invalid backup at \(url.path): \(reason)"
        case .fileCopy(let s, let d, let err):
            return "Failed to copy \(s.lastPathComponent) to \(d.path): \(err.localizedDescription)"
        }
    }
}

// MARK: - Database‑layer errors
public enum DatabaseErrorWA: Error, LocalizedError {
    case connection(Error)
    case unsupportedSchema(reason: String)
    case recordNotFound(table: String, id: CustomStringConvertible)

    public var errorDescription: String? {
        switch self {
        case .connection(let err):
            return "Database connection failed: \(err.localizedDescription)"
        case .unsupportedSchema(let reason):
            return "Unsupported database schema: \(reason)"
        case .recordNotFound(let table, let id):
            return "Record not found in \(table) with id \(id)"
        }
    }
}

// MARK: - Domain / higher‑level errors
public enum DomainError: Error, LocalizedError {
    case mediaNotFound(path: String)
    case ownerProfileNotFound
    case unexpected(reason: String)

    public var errorDescription: String? {
        switch self {
        case .mediaNotFound(let p):      return "Media not found at \(p)"
        case .ownerProfileNotFound:      return "Owner profile not found in database"
        case .unexpected(let r):         return "Unexpected error: \(r)"
        }
    }
}

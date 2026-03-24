//
//  Errors.swift
//  SwiftWABackupAPI
//
//  Created by Domingo Gallardo on 17/4/25.
//

import Foundation

/// Errors raised while discovering or copying files from an iPhone backup.
public enum BackupError: Error, LocalizedError {
    /// The backup directory could not be accessed.
    case directoryAccess(Error)

    /// A candidate backup directory is incomplete or malformed.
    case invalidBackup(url: URL, reason: String)

    /// A hashed backup file could not be copied to its destination.
    case fileCopy(source: URL, destination: URL, underlying: Error)

    /// Localized description of the error.
    public var errorDescription: String? {
        switch self {
        case .directoryAccess(let error):
            return "Failed to access backup directory: \(error.localizedDescription)"
        case .invalidBackup(let url, let reason):
            return "Invalid backup at \(url.path): \(reason)"
        case .fileCopy(let source, let destination, let error):
            return "Failed to copy \(source.lastPathComponent) to \(destination.path): \(error.localizedDescription)"
        }
    }
}

/// Errors raised while interacting with SQLite databases used by the package.
public enum DatabaseErrorWA: Error, LocalizedError {
    /// A database could not be opened or queried.
    case connection(Error)

    /// The WhatsApp schema no longer matches what the package expects.
    case unsupportedSchema(reason: String)

    /// A requested record was not found.
    case recordNotFound(table: String, id: CustomStringConvertible)

    /// Localized description of the error.
    public var errorDescription: String? {
        switch self {
        case .connection(let error):
            return "Database connection failed: \(error.localizedDescription)"
        case .unsupportedSchema(let reason):
            return "Unsupported database schema: \(reason)"
        case .recordNotFound(let table, let id):
            return "Record not found in \(table) with id \(id)"
        }
    }
}

/// Higher-level domain errors raised while interpreting WhatsApp data.
public enum DomainError: Error, LocalizedError {
    /// A referenced WhatsApp media file could not be located in the backup manifest.
    case mediaNotFound(path: String)

    /// The owner profile could not be determined from the database.
    case ownerProfileNotFound

    /// A catch-all for unexpected conditions that do not fit a narrower case.
    case unexpected(reason: String)

    /// Localized description of the error.
    public var errorDescription: String? {
        switch self {
        case .mediaNotFound(let path):
            return "Media not found at \(path)"
        case .ownerProfileNotFound:
            return "Owner profile not found in database"
        case .unexpected(let reason):
            return "Unexpected error: \(reason)"
        }
    }
}

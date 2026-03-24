//
//  BackupManager.swift
//
//
//  Created by Domingo Gallardo on 06/06/23.
//

import Foundation
import GRDB

/// Result returned when scanning a backup directory.
///
/// Valid backups contain the WhatsApp `ChatStorage.sqlite` database.
/// Invalid backups point to directories that look like iPhone backups but
/// cannot be used by this package.
public typealias BackupFetchResult = (validBackups: [IPhoneBackup], invalidBackups: [URL])

/// Scans the standard macOS backup folder and identifies usable iPhone backups.
public struct BackupManager {
    private let backupPath: String

    /// Creates a manager rooted at the provided iPhone backup directory.
    public init(backupPath: String = "~/Library/Application Support/MobileSync/Backup/") {
        self.backupPath = backupPath
    }

    /// Returns valid and invalid iPhone backup directories found under `backupPath`.
    ///
    /// Accessing the default macOS backup location may require Full Disk Access.
    public func getBackups() throws -> BackupFetchResult {
        let expandedBackupPath = NSString(string: backupPath).expandingTildeInPath
        let backupURL = URL(fileURLWithPath: expandedBackupPath)
        var validBackups: [IPhoneBackup] = []
        var invalidBackups: [URL] = []

        do {
            let directoryContents = try FileManager.default.contentsOfDirectory(
                at: backupURL,
                includingPropertiesForKeys: [.isDirectoryKey]
            )

            for url in directoryContents {
                do {
                    let resourceValues = try url.resourceValues(forKeys: [.isDirectoryKey])
                    if resourceValues.isDirectory == true {
                        validBackups.append(try getBackup(at: url))
                    }
                } catch {
                    invalidBackups.append(url)
                }
            }

            return (validBackups: validBackups, invalidBackups: invalidBackups)
        } catch {
            throw BackupError.directoryAccess(error)
        }
    }
}

extension BackupManager {
    private func getBackup(at url: URL) throws -> IPhoneBackup {
        let fileManager = FileManager.default

        guard isDirectory(at: url) else {
            throw BackupError.invalidBackup(url: url, reason: "Path is not a directory.")
        }

        let expectedFiles = ["Info.plist", "Manifest.db", "Status.plist"]
        for file in expectedFiles {
            let filePath = url.appendingPathComponent(file).path
            if !fileManager.fileExists(atPath: filePath) {
                throw BackupError.invalidBackup(url: url, reason: "\(file) is missing.")
            }
        }

        do {
            let statusPlistData = try Data(contentsOf: url.appendingPathComponent("Status.plist"))
            let plistObject = try PropertyListSerialization.propertyList(
                from: statusPlistData,
                options: [],
                format: nil
            )

            guard let plistDict = plistObject as? [String: Any],
                  let date = plistDict["Date"] as? Date else {
                throw BackupError.invalidBackup(url: url, reason: "Status.plist is malformed.")
            }

            let iPhoneBackup = IPhoneBackup(url: url, creationDate: date)

            do {
                _ = try iPhoneBackup.fetchWAFileHash(endsWith: "ChatStorage.sqlite")
            } catch {
                throw BackupError.invalidBackup(url: url, reason: "WhatsApp database not found.")
            }

            return iPhoneBackup
        } catch {
            throw BackupError.directoryAccess(error)
        }
    }

    private func isDirectory(at url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }
}

/// Relative WhatsApp filename and hashed on-disk filename stored in the iPhone backup.
public typealias FilenameAndHash = (filename: String, fileHash: String)

/// Represents an iPhone backup that contains a WhatsApp database.
public struct IPhoneBackup {
    let url: URL

    /// Absolute path of the backup directory.
    public var path: String {
        url.path
    }

    /// Creation date reported by `Status.plist`.
    public let creationDate: Date

    /// Directory name used by iTunes/Finder to identify the backup.
    public var identifier: String {
        url.lastPathComponent
    }
}

extension IPhoneBackup {
    private var manifestDBPath: String {
        url.appendingPathComponent("Manifest.db").path
    }

    private func connectToManifestDB() -> DatabaseQueue? {
        try? DatabaseQueue(path: manifestDBPath)
    }

    /// Returns the on-disk URL for a hashed file stored inside the backup.
    public func getUrl(fileHash: String) -> URL {
        url
            .appendingPathComponent(String(fileHash.prefix(2)))
            .appendingPathComponent(fileHash)
    }

    /// Resolves a WhatsApp relative path suffix to the hashed backup file identifier.
    public func fetchWAFileHash(endsWith relativePath: String) throws -> String {
        guard let manifestDb = connectToManifestDB() else {
            throw DatabaseErrorWA.connection(
                DatabaseError(message: "Unable to connect to Manifest.db")
            )
        }

        do {
            return try manifestDb.read { db in
                let row = try Row.fetchOne(
                    db,
                    sql: """
                    SELECT fileID FROM Files WHERE relativePath LIKE ?
                    AND domain = 'AppDomainGroup-group.net.whatsapp.WhatsApp.shared'
                    """,
                    arguments: ["%" + relativePath]
                )

                if let fileID: String = row?["fileID"] {
                    return fileID
                } else {
                    throw DomainError.mediaNotFound(path: relativePath)
                }
            }
        } catch {
            throw DatabaseErrorWA.connection(error)
        }
    }

    /// Returns hashed file entries whose WhatsApp relative path contains the provided fragment.
    public func fetchWAFileDetails(contains relativePath: String) -> [FilenameAndHash] {
        guard let manifestDb = connectToManifestDB() else {
            return []
        }

        var fileDetails: [FilenameAndHash] = []

        do {
            try manifestDb.read { db in
                let rows = try Row.fetchAll(
                    db,
                    sql: """
                    SELECT fileID, relativePath FROM Files WHERE relativePath LIKE ?
                    AND domain = 'AppDomainGroup-group.net.whatsapp.WhatsApp.shared'
                    """,
                    arguments: ["%" + relativePath + "%"]
                )

                for row in rows {
                    if let fileHash = row["fileID"] as? String,
                       let filename = row["relativePath"] as? String {
                        fileDetails.append((filename: filename, fileHash: fileHash))
                    }
                }
            }
        } catch {
            print("Cannot execute query: \(error)")
        }

        return fileDetails
    }
}

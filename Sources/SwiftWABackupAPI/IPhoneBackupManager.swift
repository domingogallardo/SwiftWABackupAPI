//
//  IPhoneBackupManager.swift
//
//
//  Created by Domingo Gallardo on 06/06/23.
//

import Foundation
import GRDB

/// Scans the standard macOS backup folder and identifies usable iPhone backups.
public struct IPhoneBackupManager {
    private let iPhoneBackupsPath: String

    /// Creates a manager rooted at the provided iPhone backup directory.
    public init(iPhoneBackupsPath: String = "~/Library/Application Support/MobileSync/Backup/") {
        self.iPhoneBackupsPath = iPhoneBackupsPath
    }

    /// Returns iPhone backups that are ready for WhatsApp extraction.
    ///
    /// Accessing the default macOS backup location may require Full Disk Access.
    public func getIPhoneBackups() throws -> [IPhoneBackup] {
        try inspectIPhoneBackups().compactMap { inspection in
            guard inspection.isReady else {
                return nil
            }
            return inspection.iPhoneBackup
        }
    }

    /// Returns per-backup diagnostic information, including encryption status when available.
    public func inspectIPhoneBackups() throws -> [IPhoneBackupDiscoveryInfo] {
        let expandedBackupPath = NSString(string: iPhoneBackupsPath).expandingTildeInPath
        let backupURL = URL(fileURLWithPath: expandedBackupPath)

        do {
            let directoryContents = try FileManager.default.contentsOfDirectory(
                at: backupURL,
                includingPropertiesForKeys: [.isDirectoryKey]
            )

            return try directoryContents.compactMap { url in
                let resourceValues = try url.resourceValues(forKeys: [.isDirectoryKey])
                guard resourceValues.isDirectory == true else {
                    return nil
                }

                return inspectIPhoneBackup(at: url)
            }
        } catch {
            throw BackupError.directoryAccess(error)
        }
    }
}

extension IPhoneBackupManager {
    private func isDirectory(at url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    private func inspectIPhoneBackup(at url: URL) -> IPhoneBackupDiscoveryInfo {
        let identifier = url.lastPathComponent
        let path = url.path

        guard isDirectory(at: url) else {
            return IPhoneBackupDiscoveryInfo(
                identifier: identifier,
                path: path,
                creationDate: nil,
                isEncrypted: nil,
                status: .missingRequiredFile,
                issue: "Path is not a directory."
            )
        }

        if let missingFile = firstMissingRequiredFile(at: url) {
            return IPhoneBackupDiscoveryInfo(
                identifier: identifier,
                path: path,
                creationDate: nil,
                isEncrypted: nil,
                status: .missingRequiredFile,
                issue: "\(missingFile) is missing."
            )
        }

        let backupCreationDate: Date
        do {
            backupCreationDate = try creationDate(from: url)
        } catch let error as BackupError {
            return IPhoneBackupDiscoveryInfo(
                identifier: identifier,
                path: path,
                creationDate: nil,
                isEncrypted: nil,
                status: .malformedStatusPlist,
                issue: error.errorDescription
            )
        } catch {
            return IPhoneBackupDiscoveryInfo(
                identifier: identifier,
                path: path,
                creationDate: nil,
                isEncrypted: nil,
                status: .unreadableBackup,
                issue: error.localizedDescription
            )
        }

        let encryptionInspection = encryptionState(for: url)
        let backup = IPhoneBackup(
            url: url,
            creationDate: backupCreationDate,
            isEncrypted: encryptionInspection.isEncrypted
        )

        do {
            _ = try backup.fetchWAFileHash(endsWith: "ChatStorage.sqlite")
        } catch let error as DatabaseErrorWA {
            if case .connection(let underlying) = error,
               case DomainError.mediaNotFound = underlying {
                return IPhoneBackupDiscoveryInfo(
                    identifier: identifier,
                    path: path,
                    creationDate: backupCreationDate,
                    isEncrypted: encryptionInspection.isEncrypted,
                    status: .missingWhatsAppDatabase,
                    issue: "WhatsApp database not found."
                )
            }

            return IPhoneBackupDiscoveryInfo(
                identifier: identifier,
                path: path,
                creationDate: backupCreationDate,
                isEncrypted: encryptionInspection.isEncrypted,
                status: .unreadableManifestDatabase,
                issue: error.errorDescription
            )
        } catch {
            return IPhoneBackupDiscoveryInfo(
                identifier: identifier,
                path: path,
                creationDate: backupCreationDate,
                isEncrypted: encryptionInspection.isEncrypted,
                status: .unreadableManifestDatabase,
                issue: error.localizedDescription
            )
        }

        if encryptionInspection.isEncrypted == true {
            return IPhoneBackupDiscoveryInfo(
                identifier: identifier,
                path: path,
                creationDate: backupCreationDate,
                isEncrypted: true,
                status: .encrypted,
                issue: "iPhone backup is encrypted.",
                iPhoneBackup: backup
            )
        }

        if encryptionInspection.isEncrypted == false {
            return IPhoneBackupDiscoveryInfo(
                identifier: identifier,
                path: path,
                creationDate: backupCreationDate,
                isEncrypted: false,
                status: .ready,
                issue: nil,
                iPhoneBackup: backup
            )
        }

        return IPhoneBackupDiscoveryInfo(
            identifier: identifier,
            path: path,
            creationDate: backupCreationDate,
            isEncrypted: nil,
            status: .encryptionStatusUnavailable,
            issue: encryptionInspection.issue,
            iPhoneBackup: backup
        )
    }

    private var requiredFiles: [String] {
        ["Info.plist", "Manifest.db", "Status.plist"]
    }

    private func firstMissingRequiredFile(at url: URL) -> String? {
        requiredFiles.first { file in
            !FileManager.default.fileExists(atPath: url.appendingPathComponent(file).path)
        }
    }

    private func creationDate(from url: URL) throws -> Date {
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

        return date
    }

    private func encryptionState(for url: URL) -> (isEncrypted: Bool?, issue: String?) {
        let manifestPlistURL = url.appendingPathComponent("Manifest.plist")
        guard FileManager.default.fileExists(atPath: manifestPlistURL.path) else {
            return (
                nil,
                "Manifest.plist is missing, so encryption status could not be determined."
            )
        }

        do {
            let manifestPlistData = try Data(contentsOf: manifestPlistURL)
            let plistObject = try PropertyListSerialization.propertyList(
                from: manifestPlistData,
                options: [],
                format: nil
            )

            guard let plistDict = plistObject as? [String: Any] else {
                return (
                    nil,
                    "Manifest.plist is malformed, so encryption status could not be determined."
                )
            }

            guard let isEncrypted = plistDict["IsEncrypted"] as? Bool else {
                return (
                    nil,
                    "Manifest.plist does not contain IsEncrypted, so encryption status could not be determined."
                )
            }

            return (isEncrypted, nil)
        } catch {
            return (
                nil,
                "Manifest.plist could not be read, so encryption status could not be determined: \(error.localizedDescription)"
            )
        }
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

    /// Encryption flag declared by `Manifest.plist` when available.
    public let isEncrypted: Bool?

    /// Directory name used by iTunes/Finder to identify the backup.
    public var identifier: String {
        url.lastPathComponent
    }

    init(url: URL, creationDate: Date, isEncrypted: Bool? = nil) {
        self.url = url
        self.creationDate = creationDate
        self.isEncrypted = isEncrypted
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
                    AND domain = ?
                    """,
                    arguments: ["%" + relativePath, whatsAppBackupDomain]
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
                    AND domain = ?
                    """,
                    arguments: ["%" + relativePath + "%", whatsAppBackupDomain]
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

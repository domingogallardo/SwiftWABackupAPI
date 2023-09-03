//
//  BackupManager.swift
//
//
//  Created by Domingo Gallardo on 06/06/23.
//

import Foundation
import GRDB


public enum BackupManagerError: Error {
    case directoryAccessError(error: Error)
}

// A backup is valid if it contains the WhatsApp sqlite database
public typealias BackupFetchResult = (validBackups: [IPhoneBackup], invalidBackups: [URL])

public struct BackupManager {
    // Default directory where iPhone stores backups on macOS.
    private let defaultBackupPath = "~/Library/Application Support/MobileSync/Backup/"
    
    // Fetches the list of all valid and invalid backups at the default backup path.
    // Each valid backup is represented as a IPhoneBackup struct. Invalid backups are
    // represented as a URL pointing to the invalid backup.
    //
    // The function needs permission to access 
    // ~/Library/Application Support/MobileSync/Backup/
    // Go to System Preferences -> Security & Privacy -> Full Disk Access
    public func getBackups() throws -> BackupFetchResult {
        let backupPath = NSString(string: defaultBackupPath).expandingTildeInPath
        let backupUrl = URL(fileURLWithPath: backupPath)
        var validBackups: [IPhoneBackup] = []
        var invalidBackups: [URL] = []
        do {
            let directoryContents = 
                try FileManager.default
                    .contentsOfDirectory(at: backupUrl, 
                                         includingPropertiesForKeys: nil)
            for url in directoryContents {
                if let backup = getBackup(at: url) {
                    switch backup {
                    case .valid(let backup):
                        validBackups.append(backup)
                    case .invalid(let url):
                        invalidBackups.append(url)
                    }
                }
            }
            return (validBackups: validBackups, invalidBackups: invalidBackups)
        } catch {
            throw BackupManagerError.directoryAccessError(error: error)
        }
    }

    private enum BackupResult {
        case valid(IPhoneBackup)
        case invalid(URL)
    }

    private func getBackup(at url: URL) -> BackupResult? {
        let fileManager = FileManager.default

        guard isDirectory(at: url) else {
            return nil
        }

        let expectedFiles = ["Info.plist", "Manifest.db", "Status.plist"]
        for file in expectedFiles {
            let filePath = url.appendingPathComponent(file).path
            if !fileManager.fileExists(atPath: filePath) {
                return nil
            }
        }

        do {
            let statusPlistData = 
                try Data(
                    contentsOf: url
                        .appendingPathComponent("Status.plist"))
            let plistObj = 
                try PropertyListSerialization
                    .propertyList(from: statusPlistData, 
                                  options: [], 
                                  format: nil)

                // Attempt to cast plistObj to a dictionary
                guard let plistDict = plistObj as? [String: Any],
                    let date = plistDict["Date"] as? Date else {
                    return .invalid(url)
                }

                let iPhoneBackup = IPhoneBackup(url: url, creationDate: date)

                // Check if the backup contains the WhatsApp database
                guard let chatStorageHash = iPhoneBackup.fetchWAFileHash(endsWith: "ChatStorage.sqlite") else {
                    return .invalid(url)
                }

                let chatStorageUrl = iPhoneBackup.getUrl(fileHash: chatStorageHash)

                // Attempt to create a DatabaseQueue with the given path
                guard let _ = try? DatabaseQueue(path: chatStorageUrl.path) else {
                    return .invalid(url)
                }

                return .valid(iPhoneBackup)

        } catch {
            return .invalid(url)
        }
    }

    private func isDirectory(at url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, 
                    isDirectory: &isDir) && isDir.boolValue
    }
}

public typealias FilenameAndHash = (filename: String, fileHash: String)
    
public struct IPhoneBackup {
    let url: URL
    public var path: String {
        return url.path
    }
    public let creationDate: Date
    public var identifier: String {
        return url.lastPathComponent
    }

    private var manifestDBPath: String {
        return url.appendingPathComponent("Manifest.db").path
    }

    private func connectToManifestDB() -> DatabaseQueue? {
        return try? DatabaseQueue(path: manifestDBPath)
    }

    // Returns the full URL of a hash file
    public func getUrl(fileHash: String) -> URL {
        return url
            .appendingPathComponent(String(fileHash.prefix(2)))
            .appendingPathComponent(fileHash)
    }

    // Returns the file hash of the file with a relative path in the 
    // WhatsApp backup inside the iPhone backup.
    public func fetchWAFileHash(endsWith relativePath: String) -> String? {

        guard let manifestDb = connectToManifestDB() else {
            return nil
        }

        do {
            return try manifestDb.read { db in
                let row = try Row.fetchOne(db, sql: """
                SELECT fileID FROM Files WHERE relativePath LIKE ? 
                AND domain = 'AppDomainGroup-group.net.whatsapp.WhatsApp.shared'
                """, arguments: ["%"+relativePath])
                return row?["fileID"]
            }          
        } catch {
            print("Cannot execute query: \(error)")
            return nil
        }
    }

    // Returns an array of tuples containing the filename and its corresponding
    // file hash for files that contains the relative path string in the 
    // WhatsApp backup inside the iPhone backup.
    public func fetchWAFileDetails(
        contains relativePath: String) -> [FilenameAndHash] {

        guard let manifestDb = connectToManifestDB() else {
            return []
        }

        var fileDetails: [FilenameAndHash] = []
        do {
            try manifestDb.read { db in
                let rows = try Row.fetchAll(db, sql: """
                SELECT fileID, relativePath FROM Files WHERE relativePath LIKE ? 
                AND domain = 'AppDomainGroup-group.net.whatsapp.WhatsApp.shared'
                """, arguments: ["%" + relativePath + "%"])
                for row in rows {
                    if let fileHash = row["fileID"] as? String, 
                       let filename = row["relativePath"] as? String {
                           let filenameAndHash = (filename: filename, fileHash: fileHash)
                           fileDetails.append(filenameAndHash)
                    }
                }
            }
        } catch {
            print("Cannot execute query: \(error)")
        }
        return fileDetails
    }
}

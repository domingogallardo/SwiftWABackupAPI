//
//  BackupManager.swift
//
//
//  Created by Domingo Gallardo on 06/06/23.
//

import Foundation
import GRDB

public typealias FileNameAndHash = (filename: String, fileHash: String)
    
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
        contains relativePath: String) -> [FileNameAndHash] {

        guard let manifestDb = connectToManifestDB() else {
            return []
        }

        var fileDetails: [FileNameAndHash] = []
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

struct BackupManager {
    // This is the default directory where iPhone stores backups on macOS.
    private let defaultBackupPath = "~/Library/Application Support/MobileSync/Backup/"

    // This function checks if any local backups exist at the default backup path.
    func hasLocalBackups() -> Bool {
        let backupPath = NSString(string: defaultBackupPath).expandingTildeInPath
        return FileManager.default.fileExists(atPath: backupPath)
    }

    
    // This function fetches the list of all local backups available at the default 
    // backup path.
    // Each backup is represented as a IPhoneBackup struct.
    // The function needs permission to access 
    // ~/Library/Application Support/MobileSync/Backup/
    // Go to System Preferences -> Security & Privacy -> Full Disk Access
    func getLocalBackups() -> [IPhoneBackup] {
        let backupPath = NSString(string: defaultBackupPath).expandingTildeInPath
        let backupUrl = URL(fileURLWithPath: backupPath)
        do {
            let directoryContents = 
                try FileManager.default
                    .contentsOfDirectory(at: backupUrl, 
                                         includingPropertiesForKeys: nil)
            
            // Filter out .DS_Store and return the list of backups
            return directoryContents
                .filter { !$0.lastPathComponent.hasPrefix(".DS_Store") }
                .compactMap { getBackup(at: $0 ) }
        } catch {
            print("Error while enumerating files \(backupUrl.path): \(error))")
            return []
        }
    }

    private func getBackup(at url: URL) -> IPhoneBackup? {
        let fileManager = FileManager.default

        guard isDirectory(at: url) else {
            print("Not a directory: \(url.path)")
            return nil
        }

        let expectedFiles = ["Info.plist", "Manifest.db", "Status.plist"]
        for file in expectedFiles {
            let filePath = url.appendingPathComponent(file).path
            if !fileManager.fileExists(atPath: filePath) {
                print("Directory does not contain a backup: \(url.path)")
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
            if let plistDict = plistObj as? [String: Any], 
               let date = plistDict["Date"] as? Date {
                return IPhoneBackup(url: url, creationDate: date)
            } else {
                print("Could not read Date from Status.plist in backup: " + 
                      "\(url.path)")
            }
        } catch {
            print("Error while getting backup info \(url.path): \(error)")
        }

        return nil
    }

    private func isDirectory(at url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, 
                    isDirectory: &isDir) && isDir.boolValue
    }
}

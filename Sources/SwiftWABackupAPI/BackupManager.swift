//
//  BackupManager.swift
//
//
//  Created by Domingo Gallardo on 06/06/23.
//

import Foundation
import GRDB

public struct IPhoneBackup {
    let url: URL
    public var path: String {
        return url.path
    }
    public let creationDate: Date
    public var identifier: String {
        return url.lastPathComponent
    }

    // Returns the full URL of the file given a relativePath in the WhatsApp backup
    // inside the iPhone backup.
    public func getHash(relativePath: String) -> String? {
        let fileDetails = fetchFileDetails(relativePath: relativePath)
        
        if fileDetails.isEmpty {
            return nil
        } else {
            // Access the fileHash from the first tuple
            return fileDetails[0].fileHash
        }
    }

    // Returns the full URL of a hash file
    public func getUrl(fileHash: String) -> URL {
        var backupUrl = self.url

        // Add the two first letters of the file hash to the URL
        backupUrl.appendPathComponent(String(fileHash.prefix(2)))
        // Add the file hash to the URL
        backupUrl.appendPathComponent(fileHash)
        
        return backupUrl
    }

    // Returns the file hash of the file with a relative path in the WhatsApp backup
    // inside the iPhone backup.
    public func fetchFileHash(relativePath: String) -> String? {
        var backupUrl = self.url

        // Path to the Manifest.db file
        backupUrl.appendPathComponent("Manifest.db")
        let manifestDBPath = backupUrl.path

        // Attempt to connect to the Manifest.db
        guard let manifestDb = try? DatabaseQueue(path: manifestDBPath) else {
            return nil
        }

        do {
            var fileHash: String? = nil
            try manifestDb.read { db in
                let row = try Row.fetchOne(db, sql: "SELECT fileID FROM Files WHERE relativePath LIKE ? AND domain = 'AppDomainGroup-group.net.whatsapp.WhatsApp.shared'", arguments: ["%"+relativePath])
                fileHash = row?["fileID"]
            }          
            return fileHash
        } catch {
            print("Cannot execute query: \(error)")
            return nil
        }
    }
    
    // Returns an array of tuples containing the filename and its corresponding file hash 
    // for files with a relative path in the WhatsApp backup inside the iPhone backup.
    public func fetchFileDetails(relativePath: String) -> [(filename: String, fileHash: String)] {
        var backupUrl = self.url

        // Path to the Manifest.db file
        backupUrl.appendPathComponent("Manifest.db")
        let manifestDBPath = backupUrl.path

        // Attempt to connect to the Manifest.db
        guard let manifestDb = try? DatabaseQueue(path: manifestDBPath) else {
            return []
        }

        var fileDetails: [(filename: String, fileHash: String)] = []
        do {
            try manifestDb.read { db in
                let rows = try Row.fetchAll(db, sql: "SELECT fileID, relativePath FROM Files WHERE relativePath LIKE ? AND domain = 'AppDomainGroup-group.net.whatsapp.WhatsApp.shared'", arguments: ["%" + relativePath + "%"])
                for row in rows {
                    if let fileHash = row["fileID"] as? String, let filename = row["relativePath"] as? String {
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

struct BackupManager {
    // This is the default directory where iPhone stores backups on macOS.
    let defaultBackupPath = "~/Library/Application Support/MobileSync/Backup/"

    init() {}

    // This function checks if any local backups exist at the default backup path.
    func hasLocalBackups() -> Bool {
        let fileManager = FileManager.default
        let backupPath = NSString(string: defaultBackupPath).expandingTildeInPath
        return fileManager.fileExists(atPath: backupPath)
    }

    /* 
     This function fetches the list of all local backups available at the default backup path.
     Each backup is represented as a Backup struct, containing the path to the backup 
     and its creation date.
     The function needs permission to access ~/Library/Application Support/MobileSync/Backup/
     Go to System Preferences -> Security & Privacy -> Full Disk Access
    */
    func getLocalBackups() -> [IPhoneBackup] {
        let fileManager = FileManager.default
        let backupPath = NSString(string: defaultBackupPath).expandingTildeInPath
        let backupUrl = URL(fileURLWithPath: backupPath)
        do {
            var directoryContents = try fileManager.contentsOfDirectory(at: backupUrl, includingPropertiesForKeys: nil)
            
            // Filter out .DS_Store
            directoryContents = directoryContents.filter { !$0.lastPathComponent.hasPrefix(".DS_Store") }

            return directoryContents.compactMap { url in
                return getBackup(at: url, with: fileManager)
            }
        } catch {
            print("Error while enumerating files \(backupUrl.path): \(error.localizedDescription)")
            return []
        }
    }

    private func getBackup(at url: URL, with fileManager: FileManager) -> IPhoneBackup? {
        if isDirectory(at: url, with: fileManager) {
            do {
                // Verify it is indeed a backup directory by checking for certain files
                let expectedFiles = ["Info.plist", "Manifest.db", "Status.plist"]
                for file in expectedFiles {
                    let fileURL = url.appendingPathComponent(file)
                    if !fileManager.fileExists(atPath: fileURL.path) {
                        print("Directory does not contain a backup: \(url.path)")
                        return nil
                    }
                }

                // Parse the Status.plist file for the backup date
                let statusPlistURL = url.appendingPathComponent("Status.plist")
                let statusPlistData = try Data(contentsOf: statusPlistURL)
                let plistObj = try PropertyListSerialization.propertyList(from: statusPlistData, options: [], format: nil)
                
                if let plistDict = plistObj as? [String: Any], 
                let date = plistDict["Date"] as? Date {
                    let backup = IPhoneBackup(url: url, creationDate: date)
                    return backup
                } else {
                    print("Could not read Date from Status.plist in backup: \(url.path)")
                }
            } catch {
                print("Error while getting backup info \(url.path): \(error.localizedDescription)")
            }
        } else {
            print("Not a directory: \(url.path)")
        }
        return nil
    }

    private func isDirectory(at url: URL, with fileManager: FileManager) -> Bool {
        var isDir: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }
}

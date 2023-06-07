//
//  PhoneBackup.swift
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
            let directoryContents = try fileManager.contentsOfDirectory(at: backupUrl, includingPropertiesForKeys: nil)
            return directoryContents.compactMap { url in
                return getBackup(at: url, with: fileManager)
            }
        } catch {
            print("Error while enumerating files \(backupUrl.path): \(error.localizedDescription)")
            return []
        }
    }

    func getBackup(at url: URL, with fileManager: FileManager) -> IPhoneBackup? {
        if isDirectory(at: url, with: fileManager) {
            do {
                let attributes = try fileManager.attributesOfItem(atPath: url.path)
                let creationDate = attributes[FileAttributeKey.creationDate] as? Date ?? Date()
                let backup = IPhoneBackup(url: url, creationDate: creationDate)
                return backup
            } catch {
                print("Error while getting backup info \(url.path): \(error.localizedDescription)")
                return nil
            }
        }
        return nil
    }

    func isDirectory(at url: URL, with fileManager: FileManager) -> Bool {
        var isDir: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    /*
     This function constructs the full path to the ChatStorage.sqlite file in a backup, 
     given the base path of the backup
    */
    func buildChatStoragePath(backupPath: String) -> String? {

        // Path to the Manifest.db file
        let manifestDBPath = backupPath + "/Manifest.db"

        // Attempt to connect to the Manifest.db
        guard let manifestDb = DatabaseUtils.connectToDatabase(at: manifestDBPath) else {
            return nil
        }

        // Fetch file hash of the ChatStorage.sqlite
        guard let fileHash = fetchChatStorageFileHash(from: manifestDb) else {
            return nil
        }

        // Concatenate the fileHash to the backup path to form the full path
        // Each file within the iPhone backup is stored under a path derived from its hash.
        // A hashed file path should look like this:
        // <base_backup_path>/<first two characters of file hash>/<file hash>
        return "\(backupPath)/\(fileHash.prefix(2))/\(fileHash)"
    }

    func buildChatStoragePath(backupUrl: URL) -> String? {
        var backupUrl = backupUrl

        // Path to the Manifest.db file
        backupUrl.appendPathComponent("Manifest.db")
        let manifestDBPath = backupUrl.path

        // Attempt to connect to the Manifest.db
        guard let manifestDb = DatabaseUtils.connectToDatabase(at: manifestDBPath) else {
            return nil
        }

        // Fetch file hash of the ChatStorage.sqlite
        guard let fileHash = fetchChatStorageFileHash(from: manifestDb) else {
            return nil
        }

        // Remove the Manifest.db from the URL
        backupUrl.deleteLastPathComponent()

        // Add the file hash to the URL
        backupUrl.appendPathComponent(String(fileHash.prefix(2)))
        backupUrl.appendPathComponent(fileHash)
        
        return backupUrl.path
    }

    /*
     This function fetches the file hash of ChatStorage.sqlite from the Manifest.db.
     This is required because files in the backup are stored under paths derived from their hashes. 
     It returns the file hash as a string if successful; otherwise, it returns nil.
    */
    private func fetchChatStorageFileHash(from manifestDb: DatabaseQueue) -> String? {
        let searchPath = "ChatStorage.sqlite"
        
        do {
            var fileHash: String? = nil
            try manifestDb.read { db in
                let row = try Row.fetchOne(db, sql: "SELECT fileID FROM Files WHERE relativePath = ? AND domain LIKE ?", arguments: [searchPath, "%WhatsApp%"])
                fileHash = row?["fileID"]
            }
            print("ChatStorage.sqlite file hash: \(String(describing: fileHash))")
            return fileHash
        } catch {
            print("Cannot execute query: \(error)")
            return nil
        }
    }
}

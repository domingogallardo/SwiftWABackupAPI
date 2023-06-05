//
//  SwiftWABackupAPI.swift
//
//
//  Created by Domingo Gallardo on 24/05/23.
//

import Foundation
import GRDB


public struct BackupInfo {
    public let path: String 
    public let creationDate: Date
    public var identifier: String {
        return URL(fileURLWithPath: path).lastPathComponent
    }
}

public enum ChatType: String {
    case group = "Group"
    case individual = "Individual"
    case unknown
}

public struct ChatInfo: CustomStringConvertible {
    let id: Int
    let contactJid: String
    let name: String
    let numberMessages: Int
    let lastMessageDate: Date


    public var description: String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .medium
        let localDateString = dateFormatter.string(from: lastMessageDate)

        return "Chat: ID - \(id), ContactJid - \(contactJid), " 
            + "Name - \(name), Number of Messages - \(numberMessages), "
            + "Last Message Date - \(localDateString)"
        }
}

/*
 This class is used to handle WhatsApp backups on iPhone devices. It can check 
 the existence of local backups, fetch information about these backups, and connect 
 to the SQLite database file (ChatStorage.sqlite) in the backups.
 It's primarily designed to work with the SQLite.swift library.
*/
public class WABackup {
    // This is the default directory where iPhone stores backups on macOS.
    let defaultBackupPath = "~/Library/Application Support/MobileSync/Backup/"
    // This SQLite connection will be used to interact with the ChatStorage.sqlite 
    // file in the WhatsApp backup.
    var chatStorageDb: DatabaseQueue?

    public init() {}    
    
    // This function checks if any local backups exist at the default backup path.
    public func hasLocalBackups() -> Bool {
        let fileManager = FileManager.default
        let backupPath = NSString(string: defaultBackupPath).expandingTildeInPath
        return fileManager.fileExists(atPath: backupPath)
    }

    /* 
     This function fetches the list of all local backups available at the default backup path.
     Each backup is represented as a BackupInfo struct, containing the path to the backup 
     and its creation date.
     The function needs permission to access ~/Library/Application Support/MobileSync/Backup/
     Go to System Preferences -> Security & Privacy -> Full Disk Access
    */
    public func getLocalBackups() -> [BackupInfo]? {
        let fileManager = FileManager.default
        let backupPath = NSString(string: defaultBackupPath).expandingTildeInPath
        do {
            let directoryContents = try fileManager.contentsOfDirectory(atPath: backupPath)
            return directoryContents.map { content in
                let filePath = backupPath + "/" + content
                return getBackupInfo(at: filePath, with: fileManager)
            }.compactMap { $0 }
        } catch {
            print("Error while enumerating files \(backupPath): \(error.localizedDescription)")
            return nil
        }
    }

    public func connectChatStorage(backupPath: String) {
        // Path to the Manifest.db file
        let manifestDBPath = backupPath + "/Manifest.db"

        // Attempt to connect to the Manifest.db
        guard let manifestDb = connectToDatabase(path: manifestDBPath) else {
            return
        }

        // Fetch file hash of the ChatStorage.sqlite
        guard let fileHash = fetchChatStorageFileHash(from: manifestDb) else {
            return
        }

        // Build the ChatStorage.sqlite path
        let chatStoragePath = buildChatStoragePath(backupPath: backupPath, fileHash: fileHash)

        // Attempt to connect to the ChatStorage.sqlite
        chatStorageDb = connectToDatabase(path: chatStoragePath)
    }

    public func getChats() -> [ChatInfo]? {
        guard let db = chatStorageDb else {
            print("Error: No database connection")
            return nil
        }

        var chatInfos: [ChatInfo] = []
        
        do {
            try db.read { db in
                let chatSessions = try Row.fetchAll(db, sql: "SELECT * FROM ZWACHATSESSION")
                for session in chatSessions {
                    let chatId = session["Z_PK"] as? Int64 ?? 0
                    let contactJid = session["ZCONTACTJID"] as? String ?? "Unknown"
                    let chatName = session["ZPARTNERNAME"] as? String ?? "Unknown"
                    let lastMessageDate = convertTimestampToDate(timestamp: session["ZLASTMESSAGEDATE"] as Any)
                    let numberChatMessages = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM ZWAMESSAGE WHERE ZCHATSESSION = ?", arguments: [chatId]) ?? 0
                    if numberChatMessages != 0 {
                        let chatInfo = ChatInfo(id: Int(chatId), contactJid: contactJid, name: chatName, numberMessages: numberChatMessages, lastMessageDate: lastMessageDate)
                        chatInfos.append(chatInfo)
                    }
                }
            }
            return chatInfos
        } catch {
            print("Database access error: \(error)")
            return nil
        }
    }

    private func convertTimestampToDate(timestamp: Any) -> Date {
        if let timestamp = timestamp as? Double {
            return Date(timeIntervalSinceReferenceDate: timestamp)
        } else if let timestamp = timestamp as? Int64 {
            return Date(timeIntervalSinceReferenceDate: Double(timestamp))
        }
        return Date(timeIntervalSinceReferenceDate: 0)
    }

    private func getBackupInfo(at path: String, with fileManager: FileManager) -> BackupInfo? {
        if isDirectory(at: path, with: fileManager) {
            do {
                let attributes = try fileManager.attributesOfItem(atPath: path)
                let creationDate = attributes[FileAttributeKey.creationDate] as? Date ?? Date()
                let backupInfo = BackupInfo(path: path, creationDate: creationDate)
                return backupInfo
            } catch {
                print("Error while getting backup info \(path): \(error.localizedDescription)")
                return nil
            }
        }
        return nil
    }

    private func isDirectory(at path: String, with fileManager: FileManager) -> Bool {
        var isDir: ObjCBool = false
        return fileManager.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }

    private func connectToDatabase(path: String) -> DatabaseQueue? {
        do {
            let dbQueue = try DatabaseQueue(path: path)
            return dbQueue
        } catch {
            print("Cannot connect to db at path: \(path). Error: \(error)")
            return nil
        }
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


    /*
     This function constructs the full path to the ChatStorage.sqlite file in a backup, 
     given the base path of the backup and the file hash of ChatStorage.sqlite.
    */
    private func buildChatStoragePath(backupPath: String, fileHash: String) -> String {
        // Concatenate the fileHash to the backup path to form the full path
        // Each file within the iPhone backup is stored under a path derived from its hash.
        // A hashed file path should look like this:
        // <base_backup_path>/<first two characters of file hash>/<file hash>
        return "\(backupPath)/\(fileHash.prefix(2))/\(fileHash)"
    }
}

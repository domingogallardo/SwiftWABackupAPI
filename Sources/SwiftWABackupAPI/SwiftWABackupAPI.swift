//
//  SwiftWABackupAPI.swift
//
//
//  Created by Domingo Gallardo on 24/05/23.
//

import Foundation
import SQLite

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
    let type: ChatType
    let lastMessageDate: Date?
    let name: String

    public var description: String {
        var lastMessageDateString: String
        if let lastMessageDate = lastMessageDate {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            lastMessageDateString = formatter.string(from: lastMessageDate)
        } else {
            lastMessageDateString = "No messages yet"
        }
        return "Chat Name: \(name), Chat Type: \(type.rawValue), Last Message Date: \(lastMessageDateString)"
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
    var chatStorageDb: Connection?

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


    /*
     This function attempts to connect to the ChatStorage.sqlite file in a specific backup. 
     The function first connects to the Manifest.db file in the backup to get the file hash 
     of ChatStorage.sqlite. 
     It then builds the full path to ChatStorage.sqlite using this file hash 
     Finally, it attempts to connect to the ChatStorage.sqlite file and store the connection
     in the chatStorageDb property.
    */
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

    public func getChatSessions() -> [ChatInfo] {
        let ZWACHATSESSION = Table("ZWACHATSESSION")
        let ZSESSIONTYPE = Expression<Int64>("ZSESSIONTYPE")
        let ZLASTMESSAGEDATE = Expression<Double?>("ZLASTMESSAGEDATE")
        let ZPARTNERNAME = Expression<String?>("ZPARTNERNAME")

        var chatInfos = [ChatInfo]()

        guard let chatStorageDb = chatStorageDb else {
            return chatInfos
        }
        do {
            for session in try chatStorageDb.prepare(ZWACHATSESSION.select(ZSESSIONTYPE, ZLASTMESSAGEDATE, ZPARTNERNAME)) {
                let chatType = session[ZSESSIONTYPE] == 1 ? ChatType.group : ChatType.individual
                let lastMessageDate: Date? = session[ZLASTMESSAGEDATE].map { Date(timeIntervalSinceReferenceDate: $0) }
                let chatName = session[ZPARTNERNAME] ?? "Unknown"
                let chatInfo = ChatInfo(type: chatType, lastMessageDate: lastMessageDate, name: chatName)
                chatInfos.append(chatInfo)
            }
            return chatInfos.sorted {
                switch ($0.lastMessageDate, $1.lastMessageDate) {
                case let (date1?, date2?): // Both dates are non-nil
                    return date1 > date2
                case (nil, _): // First date is nil, so it's "later"
                    return false
                default: // Second date is nil or both dates are non-nil and equal
                    return true
                }
            }
        } catch {
            print("Cannot execute query: \(error)")
            return chatInfos
        }
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

    /*
     This function attempts to connect to a SQLite database at a given path.
     If the connection is successful, it returns the Connection object; otherwise, it returns nil.
    */
    private func connectToDatabase(path: String) -> Connection? {
        do {
            let db = try Connection(path)
            // print("Connected to db at path: \(path)")
            return db
        } catch {
            // print("Cannot connect to db at path: \(path). Error: \(error)")
            return nil
        }
    }

    /*
     This function fetches the file hash of ChatStorage.sqlite from the Manifest.db.
     This is required because files in the backup are stored under paths derived from their hashes. 
     It returns the file hash as a string if successful; otherwise, it returns nil.
    */
    private func fetchChatStorageFileHash(from manifestDb: Connection) -> String? {
        let files = Table("Files")
        let fileID = Expression<String>("fileID")
        let relativePath = Expression<String>("relativePath")
        let domain = Expression<String>("domain")

        // Path to search for in the Manifest.db
        let searchPath = "ChatStorage.sqlite"

        do {
            // Search for the fileID of the file 'ChatStorage.sqlite'.
            // The domain of WatsApp app is 'AppDomainGroup-group.net.whatsapp.WhatsApp.shared'.
            // We assure that the file 'ChatStorage.sqlite' is in 
            // the 'AppDomainGroup-group.net.whatsapp.WhatsApp.shared' domain.
            let query = files.select(fileID)
                            .filter(relativePath == searchPath && domain.like("%WhatsApp%"))
            if let row = try manifestDb.pluck(query) {
                let fileHash = row[fileID]
                print("ChatStorage.sqlite file hash: \(fileHash)")
                return fileHash
            } else {
                print("Did not find the file.")
                return nil
            }
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

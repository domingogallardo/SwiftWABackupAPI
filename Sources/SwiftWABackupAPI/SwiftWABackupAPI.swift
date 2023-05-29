
import Foundation
import SQLite

public struct BackupInfo {
    public let path: String 
    public let creationDate: Date
}

public struct WABackup {
    public static let defaultBackupPath = "~/Library/Application Support/MobileSync/Backup/"

    public static func hasLocalBackup() -> Bool {
        let fileManager = FileManager.default
        let backupPath = NSString(string: defaultBackupPath).expandingTildeInPath
        return fileManager.fileExists(atPath: backupPath)
    }

    // Needs permission to access ~/Library/Application Support/MobileSync/Backup/
    // Go to System Preferences -> Security & Privacy -> Full Disk Access
    public static func getLocalBackups() -> [BackupInfo]? {
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

    private static func getBackupInfo(at path: String, with fileManager: FileManager) -> BackupInfo? {
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

    private static func isDirectory(at path: String, with fileManager: FileManager) -> Bool {
        var isDir: ObjCBool = false
        return fileManager.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }

    private static func searchChatStorage(backupPath: String) -> String? {
        // Path to the Manifest.db file
        let manifestDBPath = backupPath + "/Manifest.db"

        // Path to search for in the Manifest.db
        let searchPath = "ChatStorage.sqlite"

        let db: Connection
        do {
            db = try Connection(manifestDBPath)
        } catch {
            print("Cannot connect to db: \(error)")
            return nil
        }

        let files = Table("Files")
        let fileID = Expression<String>("fileID")
        let relativePath = Expression<String>("relativePath")
        let domain = Expression<String>("domain")
        
        do {
            // Search for the fileID of the file 'ChatStorage.sqlite'.
            // The domain of WatsApp app is 'AppDomainGroup-group.net.whatsapp.WhatsApp.shared'.
            // We assure that the file 'ChatStorage.sqlite' is in 
            // the 'AppDomainGroup-group.net.whatsapp.WhatsApp.shared' domain.
            let query = files.select(fileID)
                             .filter(relativePath == searchPath && domain.like("%WhatsApp%"))
            if let row = try db.pluck(query) {
                print("Found the file hash: \(row[fileID])")
                return row[fileID]
            } else {
                print("Did not find the file.")
                return nil
            }
        } catch {
            print("Cannot execute query: \(error)")
            return nil
        }
    }
}

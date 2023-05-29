
import Foundation

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
}

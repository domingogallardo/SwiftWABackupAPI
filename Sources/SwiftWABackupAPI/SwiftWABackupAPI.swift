
import Foundation

public struct WABackup {
    public static let defaultBackupPath = "~/Library/Application Support/MobileSync/Backup/"

    public static func hasLocalBackup() -> Bool {
        let fileManager = FileManager.default
        let backupPath = NSString(string: defaultBackupPath).expandingTildeInPath
        return fileManager.fileExists(atPath: backupPath)
    }

    // Needs permission to access ~/Library/Application Support/MobileSync/Backup/
    // Go to System Preferences -> Security & Privacy -> Full Disk Access
    public static func getLocalBackups() -> [String]? {
        let fileManager = FileManager.default
        let backupPath = NSString(string: defaultBackupPath).expandingTildeInPath
        do {
            return try fileManager.contentsOfDirectory(atPath: backupPath).filter {
                isDirectory(at: backupPath + "/" + $0, with: fileManager) 
            }
        } catch {
            print("Error while enumerating files \(backupPath): \(error.localizedDescription)")
            return nil
        }
    }

    private static func isDirectory(at path: String, with fileManager: FileManager) -> Bool {
        var isDir: ObjCBool = false
        return fileManager.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }
}

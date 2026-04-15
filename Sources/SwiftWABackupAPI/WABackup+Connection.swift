//
//  WABackup+Connection.swift
//  SwiftWABackupAPI
//

import Foundation
import GRDB

public extension WABackup {
    /// Discovers iPhone backups under the configured backup path.
    func getBackups() throws -> BackupFetchResult {
        do {
            return try phoneBackup.getBackups()
        } catch {
            throw BackupError.directoryAccess(error)
        }
    }

    /// Discovers iPhone backups together with diagnostic information such as encryption state.
    func inspectBackups() throws -> [BackupDiscoveryInfo] {
        do {
            return try phoneBackup.inspectBackups()
        } catch {
            throw BackupError.directoryAccess(error)
        }
    }

    /// Connects the API to the WhatsApp `ChatStorage.sqlite` database contained in a backup.
    ///
    /// Callers are expected to use a backup previously verified as ready by
    /// `inspectBackups()` or a backup whose `isEncrypted` flag is known to be `false`.
    func connectChatStorageDb(from backup: IPhoneBackup) throws {
        let chatStorageHash = try backup.fetchWAFileHash(endsWith: "ChatStorage.sqlite")
        let chatStorageUrl = backup.getUrl(fileHash: chatStorageHash)
        let dbQueue = try DatabaseQueue(path: chatStorageUrl.path)

        try checkSchema(of: dbQueue)

        chatDatabase = dbQueue
        iPhoneBackup = backup
        ownerJid = try dbQueue.performRead { try Message.fetchOwnerJid(from: $0) }
        mediaCopier = MediaCopier(backup: backup, delegate: delegate)
        addressBookIndex = try? AddressBookIndex.loadIfPresent(from: backup)
        lidAccountIndex = try? LidAccountIndex.loadIfPresent(from: backup)
        pushNamePhoneJidIndex = try dbQueue.performRead { try PushNamePhoneJidIndex.load(from: $0) }
    }
}

extension WABackup {
    func checkSchema(of dbQueue: DatabaseQueue) throws {
        do {
            try dbQueue.performRead { db in
                try Message.checkSchema(in: db)
                try ChatSession.checkSchema(in: db)
                try GroupMember.checkSchema(in: db)
                try ProfilePushName.checkSchema(in: db)
                try MediaItem.checkSchema(in: db)
                try MessageInfoTable.checkSchema(in: db)
            }
        } catch {
            throw DatabaseErrorWA.unsupportedSchema(reason: "Incorrect WA Database Schema")
        }
    }
}

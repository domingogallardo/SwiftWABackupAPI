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

    /// Connects the API to a WhatsApp backup previously extracted into a regular directory tree.
    func connect(to backup: ExtractedWhatsAppBackup) throws {
        try connect(using: backup)
    }

    /// Connects the API to a WhatsApp backup directory previously produced by
    /// `IPhoneBackup.extractWhatsAppBackup(to:overwriteExisting:)`.
    func connect(toWhatsAppBackupAt directory: URL) throws {
        try connect(to: ExtractedWhatsAppBackup(url: directory))
    }
}

extension WABackup {
    func connect(using fileSource: any WhatsAppFileSource) throws {
        let chatStorageUrl = try fileSource.urlForWhatsAppFile(endsWith: "ChatStorage.sqlite")
        let dbQueue = try DatabaseQueue(path: chatStorageUrl.path)

        try checkSchema(of: dbQueue)

        chatDatabase = dbQueue
        self.fileSource = fileSource
        ownerJid = try dbQueue.performRead { try Message.fetchOwnerJid(from: $0) }
        mediaCopier = MediaCopier(delegate: delegate)
        addressBookIndex = try? AddressBookIndex.loadIfPresent(from: fileSource)
        lidAccountIndex = try? LidAccountIndex.loadIfPresent(from: fileSource)
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

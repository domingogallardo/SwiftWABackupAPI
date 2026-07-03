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

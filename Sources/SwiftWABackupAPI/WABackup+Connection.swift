//
//  WABackup+Connection.swift
//  SwiftWABackupAPI
//

import Foundation
import GRDB

public extension WABackup {
    /// Returns iPhone backups that are ready for WhatsApp extraction.
    func getIPhoneBackups() throws -> [IPhoneBackup] {
        try iPhoneBackupManager.getIPhoneBackups()
    }

    /// Discovers iPhone backups together with diagnostic information such as encryption state.
    func inspectIPhoneBackups() throws -> [IPhoneBackupDiscoveryInfo] {
        try iPhoneBackupManager.inspectIPhoneBackups()
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

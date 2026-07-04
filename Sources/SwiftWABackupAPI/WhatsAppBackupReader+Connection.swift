//
//  WhatsAppBackupReader+Connection.swift
//  SwiftWABackupAPI
//

import Foundation
import GRDB

extension WhatsAppBackupReader {
    static func checkSchema(of dbQueue: DatabaseQueue) throws {
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

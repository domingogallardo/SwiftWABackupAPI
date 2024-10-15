//
//  Message.swift
//  SwiftWABackupAPI
//
//  Created by Domingo Gallardo on 3/10/24.
//

import Foundation
import GRDB

struct Message {
    let id: Int64
    let chatSessionId: Int64
    let text: String?
    let date: Date
    let isFromMe: Bool
    let messageType: Int64
    let groupMemberId: Int64?
    let mediaItemId: Int64?
    let groupEventType: Int64?
    let fromJid: String?
    let toJid: String?
    let stanzaId: String?
    
    // Define the expected columns for the ZWAMESSAGE table
    static let expectedColumns: Set<String> = [
        "Z_PK", "ZTOJID", "ZMESSAGETYPE", "ZGROUPMEMBER",
        "ZCHATSESSION", "ZTEXT", "ZMESSAGEDATE",
        "ZFROMJID", "ZMEDIAITEM", "ZISFROMME",
        "ZGROUPEVENTTYPE", "ZSTANZAID"
    ]

    // Method to check the schema of the ZWAMESSAGE table
    static func checkSchema(in db: Database) throws {
        let tableName = "ZWAMESSAGE"
        try checkTableSchema(tableName: tableName, expectedColumns: expectedColumns, in: db)
    }
    
    init(row: Row) {
        self.id = row["Z_PK"] as? Int64 ?? 0
        self.chatSessionId = row["ZCHATSESSION"] as? Int64 ?? 0
        self.text = row["ZTEXT"] as? String
        self.date = convertTimestampToDate(timestamp: row["ZMESSAGEDATE"] as Any)
        self.isFromMe = (row["ZISFROMME"] as? Int64 ?? 0) == 1
        self.messageType = row["ZMESSAGETYPE"] as? Int64 ?? -1
        self.groupMemberId = row["ZGROUPMEMBER"] as? Int64
        self.mediaItemId = row["ZMEDIAITEM"] as? Int64
        self.groupEventType = row["ZGROUPEVENTTYPE"] as? Int64
        self.fromJid = row["ZFROMJID"] as? String
        self.toJid = row["ZTOJID"] as? String
        self.stanzaId = row["ZSTANZAID"] as? String
    }

    static func fetchMessages(forChatId chatId: Int, from db: Database) throws -> [Message] {
        let supportedMessageTypes = SupportedMessageType.allValues
        let placeholders = databaseQuestionMarks(count: supportedMessageTypes.count)
        
        let sql = """
            SELECT * FROM ZWAMESSAGE
            WHERE ZCHATSESSION = ? AND ZMESSAGETYPE IN (\(placeholders))
            """
        let arguments: [DatabaseValueConvertible] = [chatId] + supportedMessageTypes
        let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(arguments))
        return rows.map { Message(row: $0) }
    }
    
    static func fetchOwnerProfilePhone(from db: Database) throws -> String? {
        let sql = """
            SELECT ZTOJID FROM ZWAMESSAGE
            WHERE ZMESSAGETYPE IN (6, 10) AND ZTOJID IS NOT NULL
            LIMIT 1
        """
        if let row = try Row.fetchOne(db, sql: sql),
           let toJid = row["ZTOJID"] as? String {
            return toJid
        }
        return nil
    }

    static func fetchOwnerJid(from db: Database) throws -> String? {
        if let ownerProfileRow = try Row.fetchOne(db, sql: """
           SELECT ZTOJID FROM ZWAMESSAGE
           WHERE ZMESSAGETYPE IN (6, 10) AND ZTOJID IS NOT NULL
           LIMIT 1
           """),
           let ownerProfileJid = ownerProfileRow["ZTOJID"] as? String {
            return ownerProfileJid
        }
        return nil
    }

    static func fetchMessageId(byStanzaId stanzaId: String, from db: Database) throws -> Int64? {
        let sql = """
            SELECT Z_PK FROM ZWAMESSAGE WHERE ZSTANZAID = ?
            """
        do {
            if let row = try Row.fetchOne(db, sql: sql, arguments: [stanzaId]) {
                return row["Z_PK"] as? Int64
            }
            return nil
        } catch {
            throw WABackupError.databaseConnectionError(error: error)
        }
    }
    
}

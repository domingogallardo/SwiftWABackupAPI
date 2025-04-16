//
//  Message.swift
//  SwiftWABackupAPI
//
//  Created by Domingo Gallardo on 3/10/24.
//  Refactor: adopta GRDBSchemaCheckable + FetchableByID
//

import Foundation
import GRDB

struct Message: FetchableByID {
    // MARK: - Protocol metadata
    static let tableName      = "ZWAMESSAGE"
    static let expectedColumns: Set<String> = [
        "Z_PK", "ZTOJID", "ZMESSAGETYPE", "ZGROUPMEMBER",
        "ZCHATSESSION", "ZTEXT", "ZMESSAGEDATE",
        "ZFROMJID", "ZMEDIAITEM", "ZISFROMME",
        "ZGROUPEVENTTYPE", "ZSTANZAID"
    ]
    static let primaryKey = "Z_PK"
    typealias Key = Int64

    // MARK: - Stored properties
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

    // MARK: - Row → Struct
    init(row: Row) {
        id            = row.value(for: "Z_PK",          default: 0)
        chatSessionId = row.value(for: "ZCHATSESSION",  default: 0)
        text          = row["ZTEXT"]
        date          = row.date(for: "ZMESSAGEDATE")
        isFromMe      = row.value(for: "ZISFROMME",     default: Int64(0)) == 1
        messageType   = row.value(for: "ZMESSAGETYPE",  default: Int64(-1))
        groupMemberId = row["ZGROUPMEMBER"]
        mediaItemId   = row["ZMEDIAITEM"]
        groupEventType = row["ZGROUPEVENTTYPE"]
        fromJid       = row["ZFROMJID"]
        toJid         = row["ZTOJID"]
        stanzaId      = row["ZSTANZAID"]
    }
}

// MARK: - Convenience API (preserva firmas previas usadas por WABackup)
extension Message {

    /// Mensajes de un chat filtrados por tipos soportados.
    static func fetchMessages(forChatId chatId: Int,
                              from db: Database) throws -> [Message] {

        let supported = SupportedMessageType.allValues
        let placeholders = supported.count.questionMarks           // Int extension
        let sql = """
            SELECT * FROM \(tableName)
            WHERE ZCHATSESSION = ? AND ZMESSAGETYPE IN (\(placeholders))
            """
        let args: [DatabaseValueConvertible] = [chatId] + supported
        return try Row.fetchAll(db, sql: sql,
                                arguments: StatementArguments(args))
                     .map(Self.init(row:))
    }

    /// Devuelve el primer `ZTOJID` que identifica al owner (perfil propio).
    static func fetchOwnerJid(from db: Database) throws -> String? {
        try Row.fetchOne(
            db,
            sql: """
                 SELECT ZTOJID FROM \(tableName)
                 WHERE ZMESSAGETYPE IN (6, 10) AND ZTOJID IS NOT NULL
                 LIMIT 1
                 """
        )?["ZTOJID"]
    }

    /// Obtiene el `Z_PK` de un mensaje a partir de su `stanzaId`.
    static func fetchMessageId(byStanzaId stanzaId: String,
                               from db: Database) throws -> Int64? {
        try Row.fetchOne(
            db,
            sql: "SELECT Z_PK FROM \(tableName) WHERE ZSTANZAID = ?",
            arguments: [stanzaId]
        )?["Z_PK"]
    }
}

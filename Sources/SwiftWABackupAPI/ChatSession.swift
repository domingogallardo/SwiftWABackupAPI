//
//  ChatSession.swift
//  SwiftWABackupAPI
//
//  Refactor: GRDBSchemaCheckable + FetchableByID
//

import Foundation
import GRDB

struct ChatSession: FetchableByID {
    // MARK:‑ Protocol metadata
    static let tableName      = "ZWACHATSESSION"
    static let expectedColumns: Set<String> = [
        "Z_PK", "ZCONTACTJID", "ZPARTNERNAME",
        "ZLASTMESSAGEDATE", "ZMESSAGECOUNTER",
        "ZSESSIONTYPE", "ZARCHIVED"
    ]
    static let primaryKey     = "Z_PK"
    typealias Key = Int64

    // MARK:‑ Stored properties
    let id: Int64
    let contactJid: String
    let partnerName: String
    let lastMessageDate: Date
    var messageCounter: Int64
    let isArchived: Bool
    let sessionType: Int64

    // MARK:‑ Computed
    var isGroupChat: Bool { contactJid.isGroupJid }

    // MARK:‑ Row → Struct
    init(row: Row) {
        id             = row.value(for: "Z_PK",            default: 0)
        contactJid     = row.value(for: "ZCONTACTJID",     default: "")
        partnerName    = row.value(for: "ZPARTNERNAME",    default: "")
        lastMessageDate = row.date(for: "ZLASTMESSAGEDATE")
        messageCounter = row.value(for: "ZMESSAGECOUNTER", default: 0)
        isArchived     = row.value(for: "ZARCHIVED",       default: Int64(0)) == 1
        sessionType    = row.value(for: "ZSESSIONTYPE",    default: 0)
    }
}

// MARK:‑ Convenience API (firmas preservadas)
extension ChatSession {

    /// Chats con al menos un mensaje distinto de STATUS.
    static func fetchAllChats(from db: Database) throws -> [ChatSession] {
        let statusType = SupportedMessageType.status.rawValue
        let supported  = SupportedMessageType.allValues
        let inClause   = supported.count.questionMarks

        let sql = """
            SELECT cs.*, COUNT(m.Z_PK) AS messageCount
            FROM \(tableName) cs
            JOIN ZWAMESSAGE m ON m.ZCHATSESSION = cs.Z_PK
            WHERE cs.ZCONTACTJID NOT LIKE ?
              AND m.ZMESSAGETYPE IN (\(inClause))
            GROUP BY cs.Z_PK
            HAVING SUM(CASE WHEN m.ZMESSAGETYPE != ? THEN 1 ELSE 0 END) > 0
            """

        var args: [DatabaseValueConvertible] = ["%@status"] + supported
        args.append(statusType)

        return try Row.fetchAll(db, sql: sql,
                                arguments: StatementArguments(args))
                     .map { row in
                         var session = ChatSession(row: row)
                         session.messageCounter =
                             row["messageCount"] as? Int64 ?? 0
                         return session
                     }
    }

    /// Chat por id o error `chatNotFound`.
    static func fetchChat(byId id: Int,
                          from db: Database) throws -> ChatSession {
        if let chat = try fetch(by: Int64(id), from: db) { return chat }
        throw DatabaseErrorWA.recordNotFound(table: "ZWACHATSESSION", id: id)
    }

    /// Nombre de la sesión para un `contactJid`.
    static func fetchChatSessionName(for contactJid: String,
                                     from db: Database) throws -> String? {
        try Row.fetchOne(
            db,
            sql: "SELECT ZPARTNERNAME FROM \(tableName) WHERE ZCONTACTJID = ?",
            arguments: [contactJid]
        )?["ZPARTNERNAME"]
    }

    // MARK:‑ SenderInfo helper usado por WABackup
    typealias SenderInfo = (senderName: String?, senderPhone: String?)

    static func fetchSenderInfo(chatId: Int,
                                from db: Database) throws -> SenderInfo {
        guard let row = try Row.fetchOne(
            db,
            sql: "SELECT ZCONTACTJID, ZPARTNERNAME FROM \(tableName) WHERE Z_PK = ?",
            arguments: [chatId]
        ) else {
            return (nil, nil)
        }
        let phone = (row["ZCONTACTJID"] as? String)?.extractedPhone
        let name  = row["ZPARTNERNAME"] as? String
        return (name, phone)
    }
}

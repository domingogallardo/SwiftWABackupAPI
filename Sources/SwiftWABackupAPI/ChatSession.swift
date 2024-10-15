//
//  ChatSession.swift
//  SwiftWABackupAPI
//
//  Created by Domingo Gallardo on 3/10/24.
//

import Foundation
import GRDB

struct ChatSession {
    let id: Int64
    let contactJid: String
    let partnerName: String
    let lastMessageDate: Date
    var messageCounter: Int64
    let isArchived: Bool
    let sessionType: Int64
    
    var isGroupChat: Bool {
            return contactJid.hasSuffix("@g.us")
    }
    
    // Define the expected columns for the ZWACHATSESSION table
    static let expectedColumns: Set<String> = [
        "Z_PK", "ZCONTACTJID", "ZPARTNERNAME",
        "ZLASTMESSAGEDATE", "ZMESSAGECOUNTER", "ZSESSIONTYPE", "ZARCHIVED"
    ]

    // Method to check the schema of the ZWACHATSESSION table
    static func checkSchema(in db: Database) throws {
        let tableName = "ZWACHATSESSION"
        try checkTableSchema(tableName: tableName, expectedColumns: expectedColumns, in: db)
    }
    
    init(row: Row) {
        self.id = row["Z_PK"] as? Int64 ?? 0
        self.contactJid = row["ZCONTACTJID"] as? String ?? ""
        self.partnerName = row["ZPARTNERNAME"] as? String ?? ""
        self.lastMessageDate = convertTimestampToDate(timestamp: row["ZLASTMESSAGEDATE"] as Any)
        self.messageCounter = row["ZMESSAGECOUNTER"] as? Int64 ?? 0
        self.isArchived = (row["ZARCHIVED"] as? Int64 ?? 0) == 1
        self.sessionType = row["ZSESSIONTYPE"] as? Int64 ?? 0
    }
    
    static func fetchAllChats(from db: Database) throws -> [ChatSession] {
        let statusType = SupportedMessageType.status.rawValue

        // Prepare the list of supported message types
        let supportedTypes = SupportedMessageType.allCases
            .map { $0.rawValue }

        // Build the placeholders for the IN clause
        let placeholders = databaseQuestionMarks(count: supportedTypes.count)

        // Obtain all the chats excepts those whose messages are of type `status`
        let sql = """
            SELECT cs.*, COUNT(m.Z_PK) as messageCount
            FROM ZWACHATSESSION cs
            JOIN ZWAMESSAGE m ON m.ZCHATSESSION = cs.Z_PK
            WHERE cs.ZCONTACTJID NOT LIKE ?
            AND m.ZMESSAGETYPE IN (\(placeholders))
            GROUP BY cs.Z_PK
            HAVING SUM(CASE WHEN m.ZMESSAGETYPE != ? THEN 1 ELSE 0 END) > 0
            """

        // Prepare the arguments, including the STATUS type for the HAVING clause
        var arguments: [DatabaseValueConvertible] = ["%@status"] + supportedTypes
        arguments.append(statusType)

        let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(arguments))
        return rows.map { row in
            var chatSession = ChatSession(row: row)
            // Actualizar el contador de mensajes con el conteo real
            chatSession.messageCounter = row["messageCount"] as? Int64 ?? 0
            return chatSession
        }
    }
    
    static func fetchChat(byId id: Int, from db: Database) throws -> ChatSession {
        let sql = """
            SELECT * FROM ZWACHATSESSION WHERE Z_PK = ?
            """
        if let row = try Row.fetchOne(db, sql: sql, arguments: [id]) {
            return ChatSession(row: row)
        } else {
            throw WABackupError.databaseConnectionError(underlyingError: DatabaseError(message: "Chat not found"))
        }
    }
    
    
    static func fetchChatSessionName(for contactJid: String, from db: Database) throws -> String? {
        let sql = """
            SELECT ZPARTNERNAME FROM ZWACHATSESSION WHERE ZCONTACTJID = ?
        """
        let arguments: [DatabaseValueConvertible] = [contactJid]
        
        if let name: String = try Row.fetchOne(db, sql: sql, arguments: StatementArguments(arguments))?["ZPARTNERNAME"] {
            return name
        }
        return nil
    }

    typealias SenderInfo = (senderName: String?, senderPhone: String?)
    
    static func fetchSenderInfo(chatId: Int, from db: Database) throws ->  SenderInfo {
        let sql = """
            SELECT ZCONTACTJID, ZPARTNERNAME FROM ZWACHATSESSION WHERE Z_PK = ?
            """
        let row = try Row.fetchOne(db, sql: sql, arguments: [chatId])
        
        if let sessionRow = row {
            let senderPhone = (sessionRow["ZCONTACTJID"] as? String)?.extractedPhone
            let senderName = sessionRow["ZPARTNERNAME"] as? String
            return (senderName, senderPhone)
        }
        return (nil, nil)
    }
}

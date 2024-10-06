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
    
    init(row: Row) {
        self.id = row["Z_PK"] as? Int64 ?? 0
        self.contactJid = row["ZCONTACTJID"] as? String ?? ""
        self.partnerName = row["ZPARTNERNAME"] as? String ?? ""
        self.lastMessageDate = convertTimestampToDate(timestamp: row["ZLASTMESSAGEDATE"] as Any)
        self.messageCounter = row["ZMESSAGECOUNTER"] as? Int64 ?? 0
        self.isArchived = (row["ZARCHIVED"] as? Int64 ?? 0) == 1
        self.sessionType = row["ZSESSIONTYPE"] as? Int64 ?? 0
    }
    
    static func fetchAllChats(from db: Database, ownerJid: String?) throws -> [ChatSession] {
        // Prepare the list of supported message types excluding Status
        let supportedTypesExcludingStatus = SupportedMessageType.allCases
            .filter { $0 != .status }
            .map { $0.rawValue }

        // Build the SQL with dynamic number of placeholders for the IN clause
        let placeholders = databaseQuestionMarks(count: supportedTypesExcludingStatus.count)

        let sql = """
            SELECT cs.*, COUNT(m.Z_PK) as messageCount
            FROM ZWACHATSESSION cs
            JOIN ZWAMESSAGE m ON m.ZCHATSESSION = cs.Z_PK
            WHERE cs.ZCONTACTJID NOT LIKE ? AND m.ZMESSAGETYPE IN (\(placeholders))
            GROUP BY cs.Z_PK
            """

        let arguments: [DatabaseValueConvertible] = ["%@status"] + supportedTypesExcludingStatus

        let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(arguments))
        return rows.map { row in
            var chatSession = ChatSession(row: row)
            // Update messageCounter with the actual count
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
            throw WABackupError.databaseConnectionError(error: DatabaseError(message: "Chat not found"))
        }
    }
}

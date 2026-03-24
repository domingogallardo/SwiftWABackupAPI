//
//  GroupMember.swift
//  SwiftWABackupAPI
//
//  Created by Domingo Gallardo on 3/10/24.
//  Refactor: adopts GRDBSchemaCheckable + FetchableByID
//

import GRDB

struct GroupMember: FetchableByID {
    // MARK: - Protocol metadata
    static let tableName      = "ZWAGROUPMEMBER"
    static let expectedColumns: Set<String> = ["Z_PK", "ZMEMBERJID", "ZCONTACTNAME"]
    static let primaryKey     = "Z_PK"
    typealias Key = Int64

    // MARK: - Stored properties
    let id: Int64
    let memberJid: String
    let contactName: String?

    // MARK: - Row → Struct
    init(row: Row) {
        id          = row.value(for: "Z_PK",        default: 0)
        memberJid   = row.value(for: "ZMEMBERJID",  default: "")
        contactName = row["ZCONTACTNAME"]
    }
}

// MARK: - Convenience API
extension GroupMember {

    /// Returns the group member by id, or `nil` when it does not exist.
    static func fetchGroupMember(byId id: Int64,
                                 from db: Database) throws -> GroupMember? {
        try fetch(by: id, from: db)
    }

    /// Returns distinct member ids that appear in supported messages for a chat.
    static func fetchGroupMemberIds(forChatId chatId: Int,
                                    from db: Database) throws -> [Int64] {

        let types = SupportedMessageType.allValues
            .map(String.init)
            .joined(separator: ", ")

        let sql = """
            SELECT DISTINCT ZGROUPMEMBER
            FROM ZWAMESSAGE
            WHERE ZCHATSESSION = ?
              AND ZMESSAGETYPE IN (\(types))
            """

        return try Row.fetchAll(db, sql: sql, arguments: [chatId])
                      .compactMap { $0["ZGROUPMEMBER"] as? Int64 }
    }

    // MARK: - Raw Sender Info
    struct GroupMemberSenderInfo {
        let memberJid: String
        let contactName: String?
    }

    static func fetchRawSenderInfo(memberId: Int,
                                   from db: Database) throws -> GroupMemberSenderInfo? {
        guard let row = try Row.fetchOne(
            db,
            sql: "SELECT ZMEMBERJID, ZCONTACTNAME FROM \(tableName) WHERE \(primaryKey) = ?",
            arguments: [memberId]
        ) else { return nil }

        guard let jid: String = row["ZMEMBERJID"] else { return nil }
        return GroupMemberSenderInfo(
            memberJid: jid,
            contactName: row["ZCONTACTNAME"]
        )
    }
}

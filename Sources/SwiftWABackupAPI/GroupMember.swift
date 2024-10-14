//
//  GroupMember.swift
//  SwiftWABackupAPI
//
//  Created by Domingo Gallardo on 3/10/24.
//


import GRDB

struct GroupMember {
    let id: Int64
    let memberJid: String
    let contactName: String?
    
    // Define the expected columns for the ZWAGROUPMEMBER table
    static let expectedColumns: Set<String> = ["Z_PK", "ZMEMBERJID", "ZCONTACTNAME"]

    // Method to check the schema of the ZWAGROUPMEMBER table
    static func checkSchema(in db: Database) throws {
        let tableName = "ZWAGROUPMEMBER"
        try checkTableSchema(tableName: tableName, expectedColumns: expectedColumns, in: db)
    }
    
    init(row: Row) {
        self.id = row["Z_PK"] as? Int64 ?? 0
        self.memberJid = row["ZMEMBERJID"] as? String ?? ""
        self.contactName = row["ZCONTACTNAME"] as? String
    }
    
    static func fetchGroupMember(byId id: Int64, from db: Database) throws -> GroupMember? {
        let sql = """
            SELECT * FROM ZWAGROUPMEMBER WHERE Z_PK = ?
            """
        if let row = try Row.fetchOne(db, sql: sql, arguments: [id]) {
            return GroupMember(row: row)
        }
        return nil
    }
    
    // Fetches all distinct group member IDs for a given chat session and supported message types.
    static func fetchGroupMemberIds(forChatId chatId: Int, from db: Database) throws -> [Int64] {
        let supportedMessageTypes = SupportedMessageType.allValues
            .map { "\($0)" }
            .joined(separator: ", ")

        // Construct the SQL query
        let sql = """
            SELECT DISTINCT ZGROUPMEMBER 
            FROM ZWAMESSAGE 
            WHERE ZCHATSESSION = ? 
            AND ZMESSAGETYPE IN (\(supportedMessageTypes))
            """
        
        // Execute the query and extract member IDs
        let rows = try Row.fetchAll(db, sql: sql, arguments: [chatId])
        let memberIds = rows.compactMap { row -> Int64? in
            return row["ZGROUPMEMBER"] as? Int64
        }
        
        return memberIds
    }
    
    // Represents the raw data needed to obtain SenderInfo.
    struct GroupMemberSenderInfo {
        let memberJid: String
        let contactName: String?
    }
    
    /// Fetches raw sender information from a group member.
    static func fetchRawSenderInfo(memberId: Int, from db: Database) throws -> GroupMemberSenderInfo? {
        let sql = """
            SELECT ZMEMBERJID, ZCONTACTNAME FROM ZWAGROUPMEMBER WHERE Z_PK = ?
            """
        guard let row = try Row.fetchOne(db, sql: sql, arguments: [memberId]) else {
            return nil
        }
        
        guard let memberJid = row["ZMEMBERJID"] as? String else {
            return nil
        }
        
        let contactName = row["ZCONTACTNAME"] as? String
        
        return GroupMemberSenderInfo(memberJid: memberJid, contactName: contactName)
    }
}

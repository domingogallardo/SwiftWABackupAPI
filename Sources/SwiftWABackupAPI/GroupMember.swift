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
}

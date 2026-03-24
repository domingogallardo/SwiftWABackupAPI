//
//  ProfilePushName.swift
//  SwiftWABackupAPI
//
//  Refactor: adopts GRDBSchemaCheckable + FetchableByID
//

import GRDB

struct ProfilePushName: FetchableByID {
    // MARK: - Protocol metadata
    static let tableName      = "ZWAPROFILEPUSHNAME"
    static let expectedColumns: Set<String> = ["ZPUSHNAME", "ZJID"]
    static let primaryKey     = "ZJID"
    typealias Key = String

    // MARK: - Stored properties
    let jid: String
    let pushName: String

    // MARK: - Row → Struct
    init(row: Row) {
        jid      = row.value(for: "ZJID",      default: "")
        pushName = row.value(for: "ZPUSHNAME", default: "")
    }
}

// MARK: - Convenience API
extension ProfilePushName {
    /// Returns the stored push name for a contact JID, if present.
    static func pushName(for contactJid: String,
                         from db: Database) throws -> String? {
        try Self.fetch(by: contactJid, from: db)?.pushName
    }
}

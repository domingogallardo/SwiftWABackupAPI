//
//  ProfilePushName.swift
//  SwiftWABackupAPI
//
//  Refactor: adopta GRDBSchemaCheckable + FetchableByID
//

import GRDB

struct ProfilePushName: FetchableByID {
    // MARK: - Protocol metadata
    static let tableName      = "ZWAPROFILEPUSHNAME"
    static let expectedColumns: Set<String> = ["ZPUSHNAME", "ZJID"]
    static let primaryKey     = "ZJID"
    typealias Key = String        // el PK es el JID (texto)

    // MARK: - Stored properties
    let jid: String
    let pushName: String

    // MARK: - Row → Struct
    init(row: Row) {
        jid      = row.value(for: "ZJID",      default: "")
        pushName = row.value(for: "ZPUSHNAME", default: "")
    }
}

// MARK: - Convenience API (opcional)
// Para mantener la firma “parecida” al método anterior.
extension ProfilePushName {
    /// Devuelve el push‑name o `nil` si no existe registro.
    static func pushName(for contactJid: String,
                         from db: Database) throws -> String? {
        try Self.fetch(by: contactJid, from: db)?.pushName
    }
}

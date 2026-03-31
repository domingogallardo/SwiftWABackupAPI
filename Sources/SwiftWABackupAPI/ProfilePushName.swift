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
    static func fetchAll(from db: Database) throws -> [ProfilePushName] {
        try Row.fetchAll(db, sql: "SELECT * FROM \(tableName)").map(Self.init(row:))
    }

    /// Returns the stored push name for a contact JID, if present.
    static func pushName(for contactJid: String,
                         from db: Database) throws -> String? {
        try Self.fetch(by: contactJid, from: db)?.pushName
    }
}

struct PushNamePhoneJidIndex {
    private let linkedPhoneJidsByLidJid: [String: String]

    init(pushNames: [ProfilePushName]) {
        let grouped = Dictionary(grouping: pushNames) {
            $0.pushName.normalizedWhatsAppDisplayText.lowercased()
        }

        var mappings: [String: String] = [:]

        for (_, rows) in grouped {
            let lidJids = Array(Set(rows.map(\.jid).filter { $0.isLidJid }))
            let phoneJids = Array(Set(rows.map(\.jid).filter { $0.isIndividualJid }))

            guard lidJids.count == 1, phoneJids.count == 1 else {
                continue
            }

            mappings[lidJids[0].lowercased()] = phoneJids[0]
        }

        linkedPhoneJidsByLidJid = mappings
    }

    static func load(from db: Database) throws -> PushNamePhoneJidIndex {
        try PushNamePhoneJidIndex(pushNames: ProfilePushName.fetchAll(from: db))
    }

    func linkedPhoneJid(for jid: String) -> String? {
        linkedPhoneJidsByLidJid[jid.lowercased()]
    }
}

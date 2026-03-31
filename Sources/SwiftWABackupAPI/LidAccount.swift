//
//  LidAccount.swift
//  SwiftWABackupAPI
//

import Foundation
import GRDB

struct LidAccount: FetchableByID {
    static let tableName = "ZWAZACCOUNT"
    static let expectedColumns: Set<String> = [
        "Z_PK",
        "ZIDENTIFIER",
        "ZPHONENUMBER",
        "ZCREATEDAT"
    ]
    static let primaryKey = "Z_PK"
    typealias Key = Int64

    let id: Int64
    let identifier: String?
    let phoneNumber: String?
    let createdAt: TimeInterval?

    init(row: Row) {
        id = row.value(for: "Z_PK", default: 0)
        identifier = row["ZIDENTIFIER"]
        phoneNumber = row["ZPHONENUMBER"]
        createdAt = row["ZCREATEDAT"]
    }
}

extension LidAccount {
    static func fetchAllResolvable(from db: Database) throws -> [LidAccount] {
        try Row.fetchAll(
            db,
            sql: """
                SELECT * FROM \(tableName)
                WHERE ZIDENTIFIER IS NOT NULL
                  AND ZIDENTIFIER LIKE '%@lid'
                  AND ZPHONENUMBER IS NOT NULL
                  AND ZPHONENUMBER != ''
                """
        ).map(Self.init(row:))
    }

    var normalizedLidJid: String? {
        guard let identifier else {
            return nil
        }

        let normalized = identifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty ? nil : normalized
    }

    var normalizedPhoneNumber: String? {
        guard let phoneNumber else {
            return nil
        }

        let digits = phoneNumber.filter(\.isNumber)
        return digits.isEmpty ? nil : digits
    }

    var resolvedPhoneJid: String? {
        guard let phone = normalizedPhoneNumber else {
            return nil
        }

        return "\(phone)@s.whatsapp.net"
    }
}

struct LidAccountIndex {
    private let byLidJid: [String: LidAccount]

    init(accounts: [LidAccount]) {
        var byLidJid: [String: LidAccount] = [:]

        for account in accounts {
            guard let lidJid = account.normalizedLidJid else {
                continue
            }

            if let existing = byLidJid[lidJid] {
                let existingCreatedAt = existing.createdAt ?? .leastNormalMagnitude
                let accountCreatedAt = account.createdAt ?? .leastNormalMagnitude

                if accountCreatedAt > existingCreatedAt {
                    byLidJid[lidJid] = account
                }
            } else {
                byLidJid[lidJid] = account
            }
        }

        self.byLidJid = byLidJid
    }

    static func loadIfPresent(from backup: IPhoneBackup) throws -> LidAccountIndex? {
        guard let fileHash = try? backup.fetchWAFileHash(endsWith: "LID.sqlite") else {
            return nil
        }

        let dbQueue = try DatabaseQueue(path: backup.getUrl(fileHash: fileHash).path)

        return try dbQueue.performRead { db in
            try LidAccount.checkSchema(in: db)
            return LidAccountIndex(accounts: try LidAccount.fetchAllResolvable(from: db))
        }
    }

    func account(for jid: String) -> LidAccount? {
        byLidJid[jid.lowercased()]
    }

    func phoneNumber(for jid: String) -> String? {
        account(for: jid)?.normalizedPhoneNumber
    }

    func phoneJid(for jid: String) -> String? {
        account(for: jid)?.resolvedPhoneJid
    }
}

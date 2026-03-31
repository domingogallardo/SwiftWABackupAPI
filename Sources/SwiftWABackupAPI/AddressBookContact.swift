//
//  AddressBookContact.swift
//  SwiftWABackupAPI
//

import Foundation
import GRDB

struct AddressBookContact: FetchableByID {
    static let tableName = "ZWAADDRESSBOOKCONTACT"
    static let expectedColumns: Set<String> = [
        "Z_PK",
        "ZFULLNAME",
        "ZGIVENNAME",
        "ZBUSINESSNAME",
        "ZLID",
        "ZPHONENUMBER",
        "ZWHATSAPPID"
    ]
    static let primaryKey = "Z_PK"
    typealias Key = Int64

    let id: Int64
    let fullName: String?
    let givenName: String?
    let businessName: String?
    let lid: String?
    let phoneNumber: String?
    let whatsAppID: String?

    init(row: Row) {
        id = row.value(for: "Z_PK", default: 0)
        fullName = row["ZFULLNAME"]
        givenName = row["ZGIVENNAME"]
        businessName = row["ZBUSINESSNAME"]
        lid = row["ZLID"]
        phoneNumber = row["ZPHONENUMBER"]
        whatsAppID = row["ZWHATSAPPID"]
    }
}

extension AddressBookContact {
    static func fetchAll(from db: Database) throws -> [AddressBookContact] {
        try Row.fetchAll(db, sql: "SELECT * FROM \(tableName)").map(Self.init(row:))
    }

    var bestDisplayName: String? {
        [fullName, businessName, givenName]
            .compactMap { $0?.normalizedWhatsAppDisplayText }
            .first(where: { !$0.isEmpty })
    }

    var bestResolvedJid: String? {
        if let whatsAppID, !whatsAppID.isEmpty {
            return whatsAppID
        }

        if let lid, !lid.isEmpty {
            return lid
        }

        return nil
    }

    var bestResolvedPhone: String? {
        if let whatsAppID, !whatsAppID.isEmpty {
            let phone = whatsAppID.extractedPhone
            if !phone.isEmpty {
                return phone
            }
        }

        if let phoneNumber {
            let digits = phoneNumber.filter(\.isNumber)
            if !digits.isEmpty {
                return digits
            }
        }

        return nil
    }
}

struct AddressBookIndex {
    private let byLidJid: [String: AddressBookContact]
    private let byWhatsAppJid: [String: AddressBookContact]
    private let byPhone: [String: AddressBookContact]

    init(contacts: [AddressBookContact]) {
        var byLidJid: [String: AddressBookContact] = [:]
        var byWhatsAppJid: [String: AddressBookContact] = [:]
        var byPhone: [String: AddressBookContact] = [:]

        for contact in contacts {
            if let lid = contact.lid?.lowercased(), !lid.isEmpty {
                byLidJid[lid] = contact
            }

            if let whatsAppJid = contact.whatsAppID?.lowercased(), !whatsAppJid.isEmpty {
                byWhatsAppJid[whatsAppJid] = contact
                let phone = whatsAppJid.extractedPhone
                if !phone.isEmpty {
                    byPhone[phone] = contact
                }
            }

            if let phone = contact.bestResolvedPhone, !phone.isEmpty, byPhone[phone] == nil {
                byPhone[phone] = contact
            }
        }

        self.byLidJid = byLidJid
        self.byWhatsAppJid = byWhatsAppJid
        self.byPhone = byPhone
    }

    static func loadIfPresent(from backup: IPhoneBackup) throws -> AddressBookIndex? {
        guard let fileHash = try? backup.fetchWAFileHash(endsWith: "ContactsV2.sqlite") else {
            return nil
        }

        let dbQueue = try DatabaseQueue(path: backup.getUrl(fileHash: fileHash).path)

        return try dbQueue.performRead { db in
            try AddressBookContact.checkSchema(in: db)
            return AddressBookIndex(contacts: try AddressBookContact.fetchAll(from: db))
        }
    }

    func contact(for jid: String) -> AddressBookContact? {
        let normalizedJid = jid.lowercased()

        if let contact = byLidJid[normalizedJid] {
            return contact
        }

        if let contact = byWhatsAppJid[normalizedJid] {
            return contact
        }

        let phone = jid.extractedPhone
        if !phone.isEmpty {
            return byPhone[phone]
        }

        return nil
    }
}

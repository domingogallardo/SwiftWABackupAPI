//
//  MessageInfoTable.swift
//  SwiftWABackupAPI
//
//  Created by Domingo Gallardo on 3/10/24.
//
//
//  Re‑implemented with GRDBSchemaCheckable + FetchableByID
//

import Foundation
import GRDB

struct MessageInfoTable: FetchableByID {
    // MARK:‑ Static metadata required by the protocols
    static let tableName      = "ZWAMESSAGEINFO"
    static let expectedColumns: Set<String> = ["ZRECEIPTINFO", "ZMESSAGE"]
    static let primaryKey     = "ZMESSAGE"         // ← clave que enlaza con ZWAMESSAGE
    typealias Key = Int      // o Int64 si prefieres

    // MARK:‑ Stored properties
    let messageId: Int64
    let receiptInfo: Data?

    // MARK:‑ Row → Struct
    init(row: Row) {
        // usa el helper Row.value(for:default:) propuesto
        messageId   = row.value(for: "ZMESSAGE", default: 0)
        receiptInfo = row["ZRECEIPTINFO"] as? Data
    }
}

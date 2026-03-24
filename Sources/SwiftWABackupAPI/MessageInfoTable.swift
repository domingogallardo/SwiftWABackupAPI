//
//  MessageInfoTable.swift
//  SwiftWABackupAPI
//
//  Created by Domingo Gallardo on 3/10/24.
//
//  Re-implemented with GRDBSchemaCheckable + FetchableByID

import Foundation
import GRDB

struct MessageInfoTable: FetchableByID {
    // MARK: - Static Metadata
    static let tableName      = "ZWAMESSAGEINFO"
    static let expectedColumns: Set<String> = ["Z_PK", "ZRECEIPTINFO", "ZMESSAGE"]
    static let primaryKey     = "ZMESSAGE"
    typealias Key = Int

    // MARK: - Stored Properties
    let messageId: Int64
    let receiptInfo: Data?

    // MARK: - Row to Struct
    init(row: Row) {
        messageId   = row.value(for: "ZMESSAGE", default: 0)
        receiptInfo = row["ZRECEIPTINFO"] as? Data
    }
}

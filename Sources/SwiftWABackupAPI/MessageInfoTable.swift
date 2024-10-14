//
//  MessageInfoTable.swift
//  SwiftWABackupAPI
//
//  Created by Domingo Gallardo on 3/10/24.
//

import Foundation
import GRDB

struct MessageInfoTable {
    let messageId: Int64
    let receiptInfo: Data?
    
    // Define the expected columns for the ZWAMESSAGEINFO table
    static let expectedColumns: Set<String> = ["ZRECEIPTINFO", "ZMESSAGE"]

    // Method to check the schema of the ZWAMESSAGEINFO table
    static func checkSchema(in db: Database) throws {
        let tableName = "ZWAMESSAGEINFO"
        try checkTableSchema(tableName: tableName, expectedColumns: expectedColumns, in: db)
    }
    
    init(row: Row) {
        self.messageId = row["ZMESSAGE"] as? Int64 ?? 0
        self.receiptInfo = row["ZRECEIPTINFO"] as? Data
    }
    
    static func fetchMessageInfo(byMessageId messageId: Int, from db: Database) throws -> MessageInfoTable? {
        let sql = """
            SELECT * FROM ZWAMESSAGEINFO WHERE ZMESSAGE = ?
            """
        do {
            if let row = try Row.fetchOne(db, sql: sql, arguments: [messageId]) {
                return MessageInfoTable(row: row)
            }
            return nil
        } catch {
            throw WABackupError.databaseConnectionError(error: error)
        }
    }
}

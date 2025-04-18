//
//  DatabaseHelpers.swift
//  SwiftWABackupAPI
//
//  Created by Domingo Gallardo on 3/10/24.
//

import GRDB


func checkTableSchema(tableName: String, expectedColumns: Set<String>, in db: Database) throws {
    // Check if the table exists
    guard try db.tableExists(tableName) else {
        throw DatabaseErrorWA.unsupportedSchema(reason: "Table \(tableName) does not exist")
    }

    // Fetch columns of the table
    let columns = try db.columns(in: tableName)
    let columnNames = Set(columns.map { $0.name.uppercased() })

    // Check if all expected fields exist in the table
    if !expectedColumns.isSubset(of: columnNames) {
        throw DatabaseErrorWA.unsupportedSchema(
            reason: "Table \(tableName) does not have all expected fields")
    }
}

//
//  DatabaseHelpers.swift
//  SwiftWABackupAPI
//
//  Created by Domingo Gallardo on 3/10/24.
//

import GRDB

func databaseQuestionMarks(count: Int) -> String {
    return Array(repeating: "?", count: count).joined(separator: ", ")
}

func checkTableSchema(tableName: String, expectedColumns: Set<String>, in db: Database) throws {
    // Check if the table exists
    guard try db.tableExists(tableName) else {
        throw WABackupError.databaseUnsupportedSchema(
            reason: "Table \(tableName) does not exist")
    }

    // Fetch columns of the table
    let columns = try db.columns(in: tableName)
    let columnNames = Set(columns.map { $0.name.uppercased() })

    // Check if all expected fields exist in the table
    if !expectedColumns.isSubset(of: columnNames) {
        throw WABackupError.databaseUnsupportedSchema(
            reason: "Table \(tableName) does not have all expected fields")
    }
}

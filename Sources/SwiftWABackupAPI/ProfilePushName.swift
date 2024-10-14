//
//  ProfilePushName.swift
//  SwiftWABackupAPI
//
//  Created by Domingo Gallardo on 3/10/24.
//


import GRDB

struct ProfilePushName {
    let jid: String
    let pushName: String
    
    // Define the expected columns for the ZWAPROFILEPUSHNAME table
    static let expectedColumns: Set<String> = ["ZPUSHNAME", "ZJID"]

    // Method to check the schema of the ZWAPROFILEPUSHNAME table
    static func checkSchema(in db: Database) throws {
        let tableName = "ZWAPROFILEPUSHNAME"
        try checkTableSchema(tableName: tableName, expectedColumns: expectedColumns, in: db)
    }
    
    init(row: Row) {
        self.jid = row["ZJID"] as? String ?? ""
        self.pushName = row["ZPUSHNAME"] as? String ?? ""
    }
    
    static func fetchProfilePushName(for contactJid: String, from db: Database) throws -> String? {
        let sql = """
            SELECT ZPUSHNAME FROM ZWAPROFILEPUSHNAME WHERE ZJID = ?
        """
        let arguments: [DatabaseValueConvertible] = [contactJid]

        if let name: String = try Row.fetchOne(db, sql: sql, arguments: StatementArguments(arguments))?["ZPUSHNAME"] {
            return name
        }
        return nil
    }
}

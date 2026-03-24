//
//  DatabaseProtocols.swift
//  SwiftWABackupAPI
//
//  Created by Domingo Gallardo on 16/4/25.
//

//
//  Protocols that remove boilerplate when working with GRDB tables.
//

import GRDB

// MARK: - GRDBSchemaCheckable
/// Conform models that need to validate their backing SQLite schema.
public protocol GRDBSchemaCheckable {
    /// Exact table name in the SQLite schema.
    static var tableName: String { get }
    /// Columns that must exist (uppercase).
    static var expectedColumns: Set<String> { get }
}

public extension GRDBSchemaCheckable {
    /// Default implementation backed by `checkTableSchema`.
    static func checkSchema(in db: Database) throws {
        try checkTableSchema(
            tableName: tableName,
            expectedColumns: expectedColumns,
            in: db
        )
    }
}

// MARK: - FetchableByID
/// Generic fetch support for rows addressed by a primary key.
public protocol FetchableByID: GRDBSchemaCheckable {
    /// Primary key type, usually `Int64`, `Int`, or `String`.
    associatedtype Key: DatabaseValueConvertible
    /// Primary key column name, for example `"Z_PK"`.
    static var primaryKey: String { get }
    
    /// Row-based initializer required by GRDB.
    init(row: Row)
}

public extension FetchableByID {
    /// Returns the model instance with the given id, or `nil` if it does not exist.
    static func fetch(by id: Key, from db: Database) throws -> Self? {
        let sql = "SELECT * FROM \(tableName) WHERE \(primaryKey) = ?"
        if let row = try Row.fetchOne(db, sql: sql, arguments: [id]) {
            return Self.init(row: row)
        }
        return nil
    }
    
    /// Convenience wrapper that throws when the record does not exist.
    static func require(by id: Key, from db: Database) throws -> Self {
        guard let value = try fetch(by: id, from: db) else {
            throw DatabaseErrorWA.recordNotFound(table: Self.tableName, id: Int64("\(id)") ?? -1)
        }
        return value
    }
}

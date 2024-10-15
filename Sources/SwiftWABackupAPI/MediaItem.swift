//
//  MediaItem.swift
//  SwiftWABackupAPI
//
//  Created by Domingo Gallardo on 3/10/24.
//

import Foundation
import GRDB

struct MediaItem {
    let id: Int64
    let localPath: String?
    let metadata: Data?
    let title: String?
    let movieDuration: Int64?
    let latitude: Double?
    let longitude: Double?
    
    // Define the expected columns for the ZWAMEDIAITEM table
    static let expectedColumns: Set<String> = ["Z_PK", "ZMETADATA", "ZTITLE", "ZMEDIALOCALPATH", "ZMOVIEDURATION", "ZLATITUDE", "ZLONGITUDE"]

    // Method to check the schema of the ZWAMEDIAITEM table
    static func checkSchema(in db: Database) throws {
        let tableName = "ZWAMEDIAITEM"
        try checkTableSchema(tableName: tableName, expectedColumns: expectedColumns, in: db)
    }
    
    init(row: Row) {
        self.id = row["Z_PK"] as? Int64 ?? 0
        self.localPath = row["ZMEDIALOCALPATH"] as? String
        self.metadata = row["ZMETADATA"] as? Data
        self.title = row["ZTITLE"] as? String
        self.movieDuration = row["ZMOVIEDURATION"] as? Int64
        self.latitude = row["ZLATITUDE"] as? Double
        self.longitude = row["ZLONGITUDE"] as? Double
    }
    
    static func fetchMediaItem(byId id: Int64, from db: Database) throws -> MediaItem? {
        let sql = """
            SELECT * FROM ZWAMEDIAITEM WHERE Z_PK = ?
            """
        do {
            if let row = try Row.fetchOne(db, sql: sql, arguments: [id]) {
                return MediaItem(row: row)
            }
            return nil
        } catch {
            throw WABackupError.databaseConnectionError(error: error)
        }
    }
    
    
    // New method to extract the reply stanzaId from metadata
    func extractReplyStanzaId() -> String? {
        guard let metadata = self.metadata else { return nil }
        return parseReplyMetadata(blob: metadata)
    }
    
    // Returns the stanza id of the message that is being replied to
    private func parseReplyMetadata(blob: Data) -> String? {
        let start = blob.startIndex.advanced(by: 2)
        var end: Int? = nil
        let endMarker: [UInt8] = [0x32, 0x1A] // hexadecimal 32 1A
        let endMarkerMe: [UInt8] = [0x9A, 0x01] // hexadecimal 9A 01 if the message
                                                // is sent by me

        for i in start..<blob.count - 1 {
            if blob[i] == endMarker[0] && blob[i+1] == endMarker[1] {
                end = i
                break
            } else if blob[i] == endMarkerMe[0] && blob[i+1] == endMarkerMe[1] {
                end = i
                break
            }
        }

        guard let endIndex = end else {
            // The end marker was not found in the blob
            return nil
        }

        // Start scanning backwards from the end marker
        var stanzaIDEnd = endIndex
        for i in (start..<endIndex).reversed() {
            let asciiValue = blob[i]
            // ASCII space is 32 (0x20) and characters less than this
            // are control characters.
            if asciiValue <= 0x20 {
                break
            }
            stanzaIDEnd = i
        }

        let stanzaIDRange = stanzaIDEnd..<endIndex
        let stanzaIDData = blob.subdata(in: stanzaIDRange)
        return String(data: stanzaIDData, encoding: .utf8)
    }
}

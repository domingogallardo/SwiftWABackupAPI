//
//  MediaItem.swift
//  SwiftWABackupAPI
//
//  Refactor: GRDBSchemaCheckable + FetchableByID
//

import Foundation
import GRDB

struct MediaItem: FetchableByID {
    // MARK:‑ Protocol metadata
    static let tableName      = "ZWAMEDIAITEM"
    static let expectedColumns: Set<String> = [
        "Z_PK", "ZMETADATA", "ZTITLE", "ZMEDIALOCALPATH",
        "ZMOVIEDURATION", "ZLATITUDE", "ZLONGITUDE"
    ]
    static let primaryKey     = "Z_PK"
    typealias Key = Int64

    // MARK:‑ Stored properties
    let id: Int64
    let localPath: String?
    let metadata: Data?
    let title: String?
    let movieDuration: Int64?
    let latitude: Double?
    let longitude: Double?

    // MARK:‑ Row → Struct
    init(row: Row) {
        id            = row.value(for: "Z_PK",             default: 0)
        localPath     = row["ZMEDIALOCALPATH"]
        metadata      = row["ZMETADATA"]  as? Data
        title         = row["ZTITLE"]
        movieDuration = row["ZMOVIEDURATION"]
        latitude      = row["ZLATITUDE"]
        longitude     = row["ZLONGITUDE"]
    }

    // MARK:‑ Convenience API (firma antigua conservada)
    static func fetchMediaItem(byId id: Int64,
                               from db: Database) throws -> MediaItem? {
        try fetch(by: id, from: db)
    }

    // MARK:‑ Reply‑metadata helpers (lógica previa intacta)
    func extractReplyStanzaId() -> String? {
        guard let metadata else { return nil }
        return parseReplyMetadata(blob: metadata)
    }

    /// Parses WA protobuf‑style metadata blob to obtain the replied‑to `stanzaId`.
    private func parseReplyMetadata(blob: Data) -> String? {
        let start = blob.startIndex.advanced(by: 2)
        let endMarker      = [UInt8(0x32), 0x1A]
        let endMarkerMe    = [UInt8(0x9A), 0x01]

        var end: Int?
        for i in start ..< blob.count - 1 {
            if (blob[i]   == endMarker[0]   && blob[i+1] == endMarker[1]) ||
               (blob[i]   == endMarkerMe[0] && blob[i+1] == endMarkerMe[1]) {
                end = i; break
            }
        }
        guard let endIndex = end else { return nil }

        var stanzaIDStart = endIndex
        for i in (start..<endIndex).reversed() {
            if blob[i] <= 0x20 { break }           // stop at control char / space
            stanzaIDStart = i
        }
        let range = stanzaIDStart..<endIndex
        return String(data: blob.subdata(in: range), encoding: .utf8)
    }
}

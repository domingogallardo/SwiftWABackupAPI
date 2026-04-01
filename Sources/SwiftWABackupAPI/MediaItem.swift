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
        return parseProtobufReplyMetadata(blob: metadata)
    }

    /// Parses modern WA protobuf-like metadata blobs and extracts the replied-to `stanzaId`.
    private func parseProtobufReplyMetadata(blob: Data) -> String? {
        let bytes = [UInt8](blob)
        var index = 0

        while index < bytes.count {
            guard let key = readVarint(from: bytes, index: &index) else {
                return nil
            }

            let fieldNumber = Int(key >> 3)
            let wireType = Int(key & 0x07)

            switch wireType {
            case 0:
                guard readVarint(from: bytes, index: &index) != nil else {
                    return nil
                }

            case 1:
                guard index + 8 <= bytes.count else {
                    return nil
                }
                index += 8

            case 2:
                guard let lengthValue = readVarint(from: bytes, index: &index),
                      let length = Int(exactly: lengthValue),
                      index + length <= bytes.count else {
                    return nil
                }

                let payload = Array(bytes[index..<(index + length)])
                index += length

                if fieldNumber == 5,
                   let stanzaId = String(bytes: payload, encoding: .utf8),
                   stanzaId.looksLikeReplyStanzaId {
                    return stanzaId
                }

            case 5:
                guard index + 4 <= bytes.count else {
                    return nil
                }
                index += 4

            default:
                return nil
            }
        }

        return nil
    }

    private func readVarint(from bytes: [UInt8], index: inout Int) -> UInt64? {
        var result: UInt64 = 0
        var shift: UInt64 = 0

        while index < bytes.count, shift <= 63 {
            let byte = bytes[index]
            index += 1
            result |= UInt64(byte & 0x7F) << shift

            if byte & 0x80 == 0 {
                return result
            }

            shift += 7
        }

        return nil
    }
}

private extension String {
    var looksLikeReplyStanzaId: Bool {
        guard !isEmpty, count <= 128, !contains("@") else {
            return false
        }

        return unicodeScalars.allSatisfy { scalar in
            !CharacterSet.whitespacesAndNewlines.contains(scalar) && !CharacterSet.controlCharacters.contains(scalar)
        }
    }
}

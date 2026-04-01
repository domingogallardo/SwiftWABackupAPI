//
//  ReactionParser.swift
//  SwiftWABackupAPI
//
//  Created by Domingo Gallardo on 17/4/25.
//
//  Parses WhatsApp `receiptInfo` blobs into `Reaction` objects.
//

import Foundation

struct ReactionParser {
    private struct ParsedReaction {
        let emoji: String
        let senderJid: String
    }

    /// Parses a WhatsApp `receiptInfo` blob into reactions.
    /// Returns `nil` when no valid reactions can be extracted.
    static func parse(
        _ data: Data,
        senderAuthorResolver: ((String) -> MessageAuthor?)? = nil
    ) -> [Reaction]? {
        let parsedReactions = extractParsedReactions(from: [UInt8](data))
        guard !parsedReactions.isEmpty else {
            return nil
        }

        let reactions = parsedReactions.compactMap { parsedReaction -> Reaction? in
            guard let author = resolveAuthor(
                for: parsedReaction.senderJid,
                senderAuthorResolver: senderAuthorResolver
            ) else {
                return nil
            }

            return Reaction(
                emoji: parsedReaction.emoji,
                author: author
            )
        }

        return reactions.isEmpty ? nil : reactions
    }

    private static func extractParsedReactions(from bytes: [UInt8]) -> [ParsedReaction] {
        var reactions: [ParsedReaction] = []
        collectParsedReactions(from: bytes, into: &reactions)
        return reactions
    }

    private static func collectParsedReactions(from bytes: [UInt8], into reactions: inout [ParsedReaction]) {
        var index = 0
        var candidateJid: String?
        var candidateEmoji: String?
        var nestedChunks: [[UInt8]] = []

        while index < bytes.count {
            guard let rawTag = readVarint(from: bytes, index: &index) else {
                return
            }

            let fieldNumber = Int(rawTag >> 3)
            let wireType = Int(rawTag & 0x07)

            switch wireType {
            case 0:
                guard readVarint(from: bytes, index: &index) != nil else {
                    return
                }
            case 1:
                guard index + 8 <= bytes.count else {
                    return
                }
                index += 8
            case 2:
                guard let length = readVarint(from: bytes, index: &index) else {
                    return
                }

                let chunkLength = Int(length)
                guard index + chunkLength <= bytes.count else {
                    return
                }

                let chunk = Array(bytes[index..<(index + chunkLength)])
                index += chunkLength
                nestedChunks.append(chunk)

                if fieldNumber == 2,
                   let candidate = decodeUTF8(chunk),
                   candidate.isReactionSenderJid {
                    candidateJid = candidate.lowercased()
                } else if fieldNumber == 3,
                          let candidate = decodeUTF8(chunk),
                          isSingleEmoji(candidate) {
                    candidateEmoji = candidate
                }
            case 5:
                guard index + 4 <= bytes.count else {
                    return
                }
                index += 4
            default:
                return
            }
        }

        if let candidateJid, let candidateEmoji {
            reactions.append(ParsedReaction(emoji: candidateEmoji, senderJid: candidateJid))
            return
        }

        for chunk in nestedChunks {
            collectParsedReactions(from: chunk, into: &reactions)
        }
    }

    private static func resolveAuthor(
        for senderJid: String,
        senderAuthorResolver: ((String) -> MessageAuthor?)?
    ) -> MessageAuthor? {
        if let resolvedAuthor = senderAuthorResolver?(senderJid) {
            return resolvedAuthor
        }

        if senderJid.isIndividualJid {
            let extractedPhone = senderJid.extractedPhone
            if !extractedPhone.isEmpty {
                return MessageAuthor(
                    kind: .participant,
                    displayName: nil,
                    phone: extractedPhone,
                    jid: senderJid,
                    source: .messageJid
                )
            }
        }

        return nil
    }

    private static func decodeUTF8(_ bytes: [UInt8]) -> String? {
        String(bytes: bytes, encoding: .utf8)
    }

    /// Checks if a string is a single emoji.
    private static func isSingleEmoji(_ string: String) -> Bool {
        guard !string.isEmpty,
              string.count == 1,
              let firstScalar = string.unicodeScalars.first else {
            return false
        }

        return firstScalar.properties.isEmoji
    }

    private static func readVarint(from bytes: [UInt8], index: inout Int) -> UInt64? {
        var result: UInt64 = 0
        var shift: UInt64 = 0

        while index < bytes.count {
            let byte = bytes[index]
            index += 1

            result |= UInt64(byte & 0x7F) << shift

            if byte & 0x80 == 0 {
                return result
            }

            shift += 7
            if shift >= 64 {
                return nil
            }
        }

        return nil
    }
}

private extension String {
    var isReactionSenderJid: Bool {
        hasSuffix("@s.whatsapp.net") || hasSuffix("@lid")
    }
}

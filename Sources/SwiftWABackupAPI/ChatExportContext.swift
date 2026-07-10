//
//  ChatExportContext.swift
//  SwiftWABackupAPI
//

import Foundation
import GRDB

/// Database-backed values needed while exporting one chat.
///
/// The context is built once per `getChat` call and discarded with the
/// resulting payload. Keeping it local prevents stale data from leaking across
/// exports and turns per-message lookups into in-memory dictionary accesses.
struct ChatExportContext {
    let chatSession: ChatSession
    let groupMembersById: [Int64: GroupMember]
    let mediaItemsById: [Int64: MediaItem]
    let messageInfoByMessageId: [Int64: MessageInfoTable]
    let messageIdsByStanzaId: [String: Int64]
    let documentMessages: [Message]
    let chatSessionNamesByJid: [String: String]

    static func load(
        chatId: Int,
        messages: [Message],
        from db: Database
    ) throws -> ChatExportContext {
        let chatSession = try ChatSession.fetchChat(byId: chatId, from: db)
        let supportedTypes = SupportedMessageType.allValues
        let placeholders = supportedTypes.count.questionMarks
        let messageArguments: [DatabaseValueConvertible] = [chatId] + supportedTypes

        let groupMembers = try Row.fetchAll(
            db,
            sql: """
                SELECT DISTINCT member.*
                FROM \(GroupMember.tableName) member
                JOIN \(Message.tableName) message
                  ON message.ZGROUPMEMBER = member.Z_PK
                WHERE message.ZCHATSESSION = ?
                  AND message.ZMESSAGETYPE IN (\(placeholders))
                """,
            arguments: StatementArguments(messageArguments)
        ).map(GroupMember.init(row:))

        let mediaItems = try Row.fetchAll(
            db,
            sql: """
                SELECT DISTINCT media.*
                FROM \(MediaItem.tableName) media
                JOIN \(Message.tableName) message
                  ON message.ZMEDIAITEM = media.Z_PK
                WHERE message.ZCHATSESSION = ?
                  AND message.ZMESSAGETYPE IN (\(placeholders))
                """,
            arguments: StatementArguments(messageArguments)
        ).map(MediaItem.init(row:))

        let messageInfoRows = try Row.fetchAll(
            db,
            sql: """
                SELECT info.*
                FROM \(MessageInfoTable.tableName) info
                JOIN \(Message.tableName) message
                  ON info.ZMESSAGE = message.Z_PK
                WHERE message.ZCHATSESSION = ?
                  AND message.ZMESSAGETYPE IN (\(placeholders))
                """,
            arguments: StatementArguments(messageArguments)
        ).map(MessageInfoTable.init(row:))

        let chatSessionNameRows = try Row.fetchAll(
            db,
            sql: """
                SELECT ZCONTACTJID, ZPARTNERNAME
                FROM \(ChatSession.tableName)
                WHERE ZSESSIONTYPE = 0
                  AND TRIM(ZPARTNERNAME) <> ''
                ORDER BY Z_PK
                """
        )

        let stanzaRows = try Row.fetchAll(
            db,
            sql: """
                SELECT Z_PK, ZSTANZAID
                FROM \(Message.tableName)
                WHERE ZCHATSESSION = ?
                  AND ZSTANZAID IS NOT NULL
                ORDER BY Z_PK
                """,
            arguments: [chatId]
        )

        var messageIdsByStanzaId: [String: Int64] = [:]
        for row in stanzaRows {
            guard let messageId: Int64 = row["Z_PK"],
                  let stanzaId: String = row["ZSTANZAID"],
                  messageIdsByStanzaId[stanzaId] == nil else {
                continue
            }
            messageIdsByStanzaId[stanzaId] = messageId
        }

        var chatSessionNamesByJid: [String: String] = [:]
        for row in chatSessionNameRows {
            guard let jid: String = row["ZCONTACTJID"],
                  let name: String = row["ZPARTNERNAME"],
                  chatSessionNamesByJid[jid] == nil else {
                continue
            }
            chatSessionNamesByJid[jid] = name
        }

        var messageInfoByMessageId: [Int64: MessageInfoTable] = [:]
        for messageInfo in messageInfoRows where messageInfoByMessageId[messageInfo.messageId] == nil {
            messageInfoByMessageId[messageInfo.messageId] = messageInfo
        }

        return ChatExportContext(
            chatSession: chatSession,
            groupMembersById: Dictionary(uniqueKeysWithValues: groupMembers.map { ($0.id, $0) }),
            mediaItemsById: Dictionary(uniqueKeysWithValues: mediaItems.map { ($0.id, $0) }),
            messageInfoByMessageId: messageInfoByMessageId,
            messageIdsByStanzaId: messageIdsByStanzaId,
            documentMessages: messages.filter {
                $0.messageType == SupportedMessageType.doc.rawValue && $0.text != nil
            },
            chatSessionNamesByJid: chatSessionNamesByJid
        )
    }

    func duplicateDocumentCandidates(for message: Message) -> [Message] {
        let searchWindowStart = message.date.addingTimeInterval(-12 * 60 * 60)
        var lowerBound = 0
        var upperBound = documentMessages.count

        while lowerBound < upperBound {
            let middle = lowerBound + (upperBound - lowerBound) / 2
            if documentMessages[middle].date <= message.date {
                lowerBound = middle + 1
            } else {
                upperBound = middle
            }
        }

        var candidates: [Message] = []
        candidates.reserveCapacity(25)
        var index = lowerBound - 1

        while index >= 0, candidates.count < 25 {
            let candidate = documentMessages[index]
            guard candidate.date >= searchWindowStart else {
                break
            }

            if candidate.id != message.id {
                candidates.append(candidate)
            }
            index -= 1
        }

        return candidates
    }
}

struct ParticipantAuthorCacheKey: Hashable {
    let jid: String
    let contactName: String?
    let fallbackSource: String
}

/// Mutable state whose lifetime is limited to one chat export.
final class ChatExportState {
    let context: ChatExportContext
    var authorsByKey: [ParticipantAuthorCacheKey: MessageAuthor] = [:]

    init(context: ChatExportContext) {
        self.context = context
    }
}

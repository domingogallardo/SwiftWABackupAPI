//
//  PreparedChatDocument.swift
//  SwiftWABackupAPI
//

import Foundation

/// Versioned, decodable representation of a chat prepared for persistent storage.
public struct PreparedChatDocument: Codable {
    /// Schema version emitted and accepted by this package release.
    public static let currentSchemaVersion = 1

    /// Version of the prepared-chat JSON schema.
    public let schemaVersion: Int

    /// Date when this document was generated.
    public let generatedAt: Date

    /// Chat metadata captured in the document.
    public let chat: ChatInfo

    /// Messages captured in chronological order.
    public let messages: [MessageInfo]

    /// Contacts resolved for the chat.
    public let contacts: [ContactInfo]

    /// Creates a current-version document from an in-memory chat payload.
    public init(payload: ChatDumpPayload, generatedAt: Date = Date()) {
        self.schemaVersion = Self.currentSchemaVersion
        self.generatedAt = generatedAt
        self.chat = payload.chatInfo
        self.messages = payload.messages
        self.contacts = payload.contacts
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case generatedAt
        case chat
        case messages
        case contacts
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)

        guard schemaVersion == Self.currentSchemaVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: container,
                debugDescription: "Unsupported prepared chat schema version: \(schemaVersion)"
            )
        }

        self.schemaVersion = schemaVersion
        self.generatedAt = try container.decode(Date.self, forKey: .generatedAt)
        self.chat = try container.decode(ChatInfo.self, forKey: .chat)
        self.messages = try container.decode([MessageInfo].self, forKey: .messages)
        self.contacts = try container.decode([ContactInfo].self, forKey: .contacts)
    }
}

//
//  ExportedChat.swift
//  SwiftWABackupAPI
//

import Foundation

/// Versioned, persistent representation of a fully exported chat.
public struct ExportedChatDocument: Codable {
    /// Schema version emitted and accepted by this package release.
    public static let currentSchemaVersion = 1

    /// Version of the exported-chat JSON schema.
    public let schemaVersion: Int

    /// Date when the chat export completed.
    public let exportedAt: Date

    /// Chat metadata captured at export time.
    public let chat: ChatInfo

    /// Exported messages in chronological order.
    public let messages: [MessageInfo]

    /// Contacts resolved for the exported chat.
    public let contacts: [ContactInfo]

    /// Creates a current-version document from an in-memory chat payload.
    public init(payload: ChatDumpPayload, exportedAt: Date = Date()) {
        self.schemaVersion = Self.currentSchemaVersion
        self.exportedAt = exportedAt
        self.chat = payload.chatInfo
        self.messages = payload.messages
        self.contacts = payload.contacts
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case exportedAt
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
                debugDescription: "Unsupported exported chat schema version: \(schemaVersion)"
            )
        }

        self.schemaVersion = schemaVersion
        self.exportedAt = try container.decode(Date.self, forKey: .exportedAt)
        self.chat = try container.decode(ChatInfo.self, forKey: .chat)
        self.messages = try container.decode([MessageInfo].self, forKey: .messages)
        self.contacts = try container.decode([ContactInfo].self, forKey: .contacts)
    }
}

/// A chat export opened from its self-contained directory.
public struct ExportedChat {
    /// Decoded export document.
    public let document: ExportedChatDocument

    /// Directory that contains `chat.json` and `Media`.
    public let directoryURL: URL

    /// URL of the versioned JSON document.
    public let documentURL: URL

    /// Directory containing copied message and contact media.
    public let mediaDirectoryURL: URL
}

/// Metadata used to describe a valid or stale chat export.
public struct ChatExportInfo: Codable, Equatable {
    /// Stable identifier of the exported chat.
    public let chatId: Int

    /// WhatsApp JID captured at export time.
    public let contactJid: String

    /// Date when the export completed.
    public let exportedAt: Date

    /// Supported-message count captured at export time.
    public let numberMessages: Int

    /// Latest supported-message date captured at export time.
    public let lastMessageDate: Date

    /// Version of the exported-chat document schema.
    public let schemaVersion: Int

    /// Directory containing `chat.json` and `Media`.
    public let directoryURL: URL
}

/// Persistent export state for a chat listed from the source backup.
public enum ChatExportState: Equatable {
    /// No export directory exists for this chat.
    case notExported

    /// A complete export matches the current source metadata.
    case exported(ChatExportInfo)

    /// A complete export exists but no longer matches the source metadata.
    case stale(ChatExportInfo)

    /// An export directory exists but cannot be opened safely.
    case invalid(reason: String)
}

/// Errors raised while creating or opening self-contained chat exports.
public enum ChatExportError: Error, LocalizedError {
    /// The reader has no export root configured.
    case exportRootNotConfigured

    /// A chat export already exists and replacement was not requested.
    case alreadyExists(chatId: Int, directory: URL)

    /// No complete chat export exists at the expected location.
    case notFound(chatId: Int, directory: URL)

    /// The JSON document or copied files do not form a valid export.
    case invalidDocument(url: URL, reason: String)

    /// A file-system operation failed while managing an export.
    case fileOperation(url: URL, underlying: Error)

    public var errorDescription: String? {
        switch self {
        case .exportRootNotConfigured:
            return "The WhatsApp backup reader has no export root configured."
        case .alreadyExists(let chatId, let directory):
            return "Chat \(chatId) is already exported at \(directory.path)."
        case .notFound(let chatId, let directory):
            return "No exported chat \(chatId) was found at \(directory.path)."
        case .invalidDocument(let url, let reason):
            return "Invalid exported chat at \(url.path): \(reason)"
        case .fileOperation(let url, let error):
            return "Failed to manage chat export at \(url.path): \(error.localizedDescription)"
        }
    }
}

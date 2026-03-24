//
//  SwiftWABackupAPI.swift
//
//  Created by Domingo Gallardo on 24/05/23.
//
//  This module provides an API for accessing and processing WhatsApp databases
//  extracted from iOS backups. It includes functionality for reading chats,
//  messages, contacts, and associated media files.
//

import Foundation
import GRDB

/// Represents a WhatsApp chat returned by the public API.
public struct ChatInfo: CustomStringConvertible, Encodable {
    /// The supported chat categories exposed by the API.
    public enum ChatType: String, Codable {
        /// A multi-participant WhatsApp group.
        case group

        /// A one-to-one WhatsApp conversation.
        case individual
    }

    /// Stable identifier of the chat session in `ZWACHATSESSION`.
    public let id: Int

    /// Raw WhatsApp JID associated with the chat.
    public let contactJid: String

    /// Display name resolved for the chat.
    public let name: String

    /// Number of supported messages available through the API.
    public let numberMessages: Int

    /// Date of the latest supported message in the chat.
    public let lastMessageDate: Date

    /// The chat category derived from the contact JID.
    public let chatType: ChatType

    /// Indicates whether the chat is archived in WhatsApp.
    public let isArchived: Bool

    /// Copied profile image filename when `directoryToSavePhotos` is provided.
    public var photoFilename: String?

    init(
        id: Int,
        contactJid: String,
        name: String,
        numberMessages: Int,
        lastMessageDate: Date,
        isArchived: Bool,
        photoFilename: String? = nil
    ) {
        self.id = id
        self.contactJid = contactJid
        self.name = name
        self.numberMessages = numberMessages
        self.lastMessageDate = lastMessageDate
        self.isArchived = isArchived
        self.chatType = contactJid.isGroupJid ? .group : .individual
        self.photoFilename = photoFilename
    }

    /// A human-readable description intended for debugging.
    public var description: String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .medium
        let localDateString = dateFormatter.string(from: lastMessageDate)

        return "Chat: ID - \(id), ContactJid - \(contactJid), "
            + "Name - \(name), Number of Messages - \(numberMessages), "
            + "Last Message Date - \(localDateString), "
            + "Chat Type - \(chatType.rawValue), "
            + "Is Archived - \(isArchived), "
            + "Photo Filename - \(photoFilename ?? "None")"
    }
}

/// Represents a reaction attached to a message.
public struct Reaction: Encodable {
    /// Emoji chosen by the reactor.
    public let emoji: String

    /// Phone number extracted from the reacting JID, or `"Me"` for the owner.
    public let senderPhone: String
}

/// Represents the structured author identity resolved for a message.
public struct MessageAuthor: Encodable {
    /// High-level category of message author.
    public enum Kind: String, Codable {
        /// The owner of the backup sent the message.
        case me

        /// Another WhatsApp participant sent the message.
        case participant
    }

    /// Source used to resolve the author identity.
    public enum Source: String, Codable {
        /// Resolved from the owner identity detected in the backup.
        case owner

        /// Resolved from `ZWACHATSESSION`.
        case chatSession

        /// Resolved from `ZWAPROFILEPUSHNAME`.
        case pushName

        /// Resolved from `ZWAGROUPMEMBER`.
        case groupMember

        /// Resolved from the raw message JID stored in `ZWAMESSAGE`.
        case messageJid
    }

    /// Whether the author is the owner or another participant.
    public let kind: Kind

    /// Best-effort display name selected by the API.
    public let displayName: String?

    /// Phone-like user portion derived from the WhatsApp JID.
    public let phone: String?

    /// Raw WhatsApp JID when it can be determined.
    public let jid: String?

    /// Source used by the API to resolve the author.
    public let source: Source
}

enum SupportedMessageType: Int64, CaseIterable {
    case text = 0
    case image = 1
    case video = 2
    case audio = 3
    case contact = 4
    case location = 5
    case link = 7
    case doc = 8
    case status = 10
    case gif = 11
    case sticker = 15

    var description: String {
        switch self {
        case .text: return "Text"
        case .image: return "Image"
        case .video: return "Video"
        case .audio: return "Audio"
        case .contact: return "Contact"
        case .location: return "Location"
        case .link: return "Link"
        case .doc: return "Document"
        case .status: return "Status"
        case .gif: return "GIF"
        case .sticker: return "Sticker"
        }
    }

    /// Returns all supported message types as an array of raw values.
    static var allValues: [Int64] {
        Self.allCases.map(\.rawValue)
    }
}

/// Represents a WhatsApp message returned by the public API.
public struct MessageInfo: CustomStringConvertible, Encodable {
    /// Stable identifier of the message in `ZWAMESSAGE`.
    public let id: Int

    /// Identifier of the parent chat session.
    public let chatId: Int

    /// Message text or event text resolved by the API.
    public let message: String?

    /// Message timestamp.
    public let date: Date

    /// Indicates whether the message was sent by the owner.
    public let isFromMe: Bool

    /// Human-readable message type name.
    public let messageType: String

    /// Structured author identity for the message when it can be resolved.
    public var author: MessageAuthor?

    /// Caption or title associated with linked media.
    public var caption: String?

    /// Identifier of the replied-to message when it can be resolved.
    public var replyTo: Int?

    /// Filename of copied media when export is requested.
    public var mediaFilename: String?

    /// Parsed reactions for this message.
    public var reactions: [Reaction]?

    /// Optional textual warning associated with media processing.
    public var error: String?

    /// Duration in seconds for audio and video messages.
    public var seconds: Int?

    /// Latitude for location messages.
    public var latitude: Double?

    /// Longitude for location messages.
    public var longitude: Double?

    init(
        id: Int,
        chatId: Int,
        message: String?,
        date: Date,
        isFromMe: Bool,
        messageType: String,
        author: MessageAuthor? = nil
    ) {
        self.id = id
        self.chatId = chatId
        self.message = message
        self.date = date
        self.isFromMe = isFromMe
        self.messageType = messageType
        self.author = author
        self.caption = nil
        self.replyTo = nil
        self.mediaFilename = nil
        self.reactions = nil
        self.error = nil
        self.seconds = nil
        self.latitude = nil
        self.longitude = nil
    }

    /// A human-readable description intended for debugging.
    public var description: String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .medium
        let localDateString = dateFormatter.string(from: date)

        return """
        Message: ID - \(id), IsFromMe - \(isFromMe), Message - \
        \(message ?? ""), Date - \(localDateString)
        """
    }
}

/// Represents a contact returned alongside a chat export.
public struct ContactInfo: CustomStringConvertible, Encodable, Hashable {
    /// Resolved display name for the contact.
    public let name: String

    /// Phone number derived from the contact JID.
    public let phone: String

    /// Copied profile image filename when available.
    public var photoFilename: String?

    /// A human-readable description intended for debugging.
    public var description: String {
        "Contact: Phone - \(phone), Name - \(name)"
    }

    /// Hashes the contact by phone number so contact sets remain stable.
    public func hash(into hasher: inout Hasher) {
        hasher.combine(phone)
    }

    /// Contacts are considered equal when they refer to the same phone number.
    public static func == (lhs: ContactInfo, rhs: ContactInfo) -> Bool {
        lhs.phone == rhs.phone
    }
}

/// Legacy tuple returned by `getChat(chatId:directoryToSaveMedia:)`.
public typealias ChatDump = (chatInfo: ChatInfo, messages: [MessageInfo], contacts: [ContactInfo])

/// Encodable wrapper around a full chat export.
public struct ChatDumpPayload: CustomStringConvertible, Encodable {
    /// Chat metadata for the exported conversation.
    public let chatInfo: ChatInfo

    /// Messages returned for the chat.
    public let messages: [MessageInfo]

    /// Contacts resolved for the chat.
    public let contacts: [ContactInfo]

    /// Creates a payload from its individual components.
    public init(chatInfo: ChatInfo, messages: [MessageInfo], contacts: [ContactInfo]) {
        self.chatInfo = chatInfo
        self.messages = messages
        self.contacts = contacts
    }

    /// Creates a payload from the legacy `ChatDump` tuple.
    public init(_ chatDump: ChatDump) {
        self.init(
            chatInfo: chatDump.chatInfo,
            messages: chatDump.messages,
            contacts: chatDump.contacts
        )
    }

    /// A human-readable description intended for debugging.
    public var description: String {
        "ChatDumpPayload(chatId: \(chatInfo.id), messages: \(messages.count), contacts: \(contacts.count))"
    }
}

/// Receives callbacks when media files are copied to disk.
public protocol WABackupDelegate: AnyObject {
    /// Called after a media file is copied or already exists in the output directory.
    func didWriteMediaFile(fileName: String)
}

extension DatabaseQueue {
    func performRead<T>(_ block: (Database) throws -> T) throws -> T {
        do {
            return try read(block)
        } catch {
            throw DatabaseErrorWA.connection(error)
        }
    }
}

/// Main entry point for exploring a WhatsApp iPhone backup.
public class WABackup {
    var phoneBackup: BackupManager

    /// Delegate used to observe media export events.
    public weak var delegate: WABackupDelegate? {
        didSet {
            mediaCopier?.delegate = delegate
        }
    }

    var chatDatabase: DatabaseQueue?
    var iPhoneBackup: IPhoneBackup?
    var ownerJid: String?
    var mediaCopier: MediaCopier?

    /// Creates a backup explorer rooted at the provided iPhone backup directory.
    public init(backupPath: String = "~/Library/Application Support/MobileSync/Backup/") {
        self.phoneBackup = BackupManager(backupPath: backupPath)
    }
}

import Foundation

/// Relative author stored in a portable conversation.
public struct PortableMessageAuthor: Codable, Hashable, Sendable {
    public enum Role: String, Codable, Sendable {
        case sourceUser
        case participant
        case unresolved
    }

    public let role: Role
    public let identityHint: CanonicalParticipantIdentity?
    public let displayName: String?

    public init(
        role: Role,
        identityHint: CanonicalParticipantIdentity? = nil,
        displayName: String? = nil
    ) {
        self.role = role
        self.identityHint = identityHint
        self.displayName = displayName
    }
}

/// Application that requested creation of a portable archive.
public struct PortableArchiveProducer: Codable, Hashable, Sendable {
    public let name: String
    public let version: String

    public init(name: String, version: String) {
        self.name = name
        self.version = version
    }
}

/// Codec implementation recorded in a portable manifest.
public struct PortableArchiveImplementation: Codable, Hashable, Sendable {
    public let name: String
    public let formatVersion: Int
    public let algorithmVersion: Int

    public init(name: String, formatVersion: Int, algorithmVersion: Int) {
        self.name = name
        self.formatVersion = formatVersion
        self.algorithmVersion = algorithmVersion
    }
}

/// Conversation metadata expressed from the source document's perspective.
public struct PortableConversationDescriptor: Codable, Hashable, Sendable {
    public let chatType: ChatInfo.ChatType
    public let groupJID: String?
    public let contactJID: String?
    public let contactIdentity: CanonicalParticipantIdentity?
    public let displayName: String
    public let isArchived: Bool
    public let exportedAt: Date
    public let photoPath: String?

    public init(
        chatType: ChatInfo.ChatType,
        groupJID: String? = nil,
        contactJID: String? = nil,
        contactIdentity: CanonicalParticipantIdentity? = nil,
        displayName: String,
        isArchived: Bool,
        exportedAt: Date,
        photoPath: String? = nil
    ) {
        self.chatType = chatType
        self.groupJID = groupJID
        self.contactJID = contactJID
        self.contactIdentity = contactIdentity
        self.displayName = displayName
        self.isArchived = isArchived
        self.exportedAt = exportedAt
        self.photoPath = photoPath
    }
}

/// Size and digest of one regular file stored in a portable archive.
public struct PortableFileEntry: Codable, Hashable, Sendable {
    public let path: String
    public let byteCount: Int64
    public let sha256: String

    public init(path: String, byteCount: Int64, sha256: String) {
        self.path = path
        self.byteCount = byteCount
        self.sha256 = sha256
    }
}

/// Declared media file stored below `Media/`.
public struct PortableMediaEntry: Codable, Hashable, Sendable {
    public let path: String
    public let byteCount: Int64
    public let sha256: String

    public init(path: String, byteCount: Int64, sha256: String) {
        self.path = path
        self.byteCount = byteCount
        self.sha256 = sha256
    }
}

/// Versioned manifest at the root of a `.fmcchat` archive.
public struct PortableConversationManifest: Codable, Sendable {
    public static let currentSchemaVersion = 1
    public static let formatIdentifier =
        "com.domingogallardo.freemychats.portable-conversation"

    public let schemaVersion: Int
    public let format: String
    public let packageID: UUID
    public let createdAt: Date
    public let producer: PortableArchiveProducer
    public let implementation: PortableArchiveImplementation
    public let conversation: PortableConversationDescriptor
    public let messageCount: Int
    public let firstMessageAt: Date?
    public let lastMessageAt: Date?
    public let document: PortableFileEntry
    public let media: [PortableMediaEntry]
    public let contentDigest: String

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        format: String = Self.formatIdentifier,
        packageID: UUID,
        createdAt: Date,
        producer: PortableArchiveProducer,
        implementation: PortableArchiveImplementation,
        conversation: PortableConversationDescriptor,
        messageCount: Int,
        firstMessageAt: Date?,
        lastMessageAt: Date?,
        document: PortableFileEntry,
        media: [PortableMediaEntry],
        contentDigest: String
    ) {
        self.schemaVersion = schemaVersion
        self.format = format
        self.packageID = packageID
        self.createdAt = createdAt
        self.producer = producer
        self.implementation = implementation
        self.conversation = conversation
        self.messageCount = messageCount
        self.firstMessageAt = firstMessageAt
        self.lastMessageAt = lastMessageAt
        self.document = document
        self.media = media
        self.contentDigest = contentDigest
    }
}

/// Portable contact independent from source database identifiers.
public struct PortableContact: Codable, Hashable, Sendable {
    public let identity: CanonicalParticipantIdentity
    public let displayName: String
    public let photoPath: String?

    public init(
        identity: CanonicalParticipantIdentity,
        displayName: String,
        photoPath: String? = nil
    ) {
        self.identity = identity
        self.displayName = displayName
        self.photoPath = photoPath
    }
}

/// Reaction whose author remains relative to the portable source.
public struct PortableReaction: Codable, Hashable, Sendable {
    public let emoji: String
    public let author: PortableMessageAuthor

    public init(emoji: String, author: PortableMessageAuthor) {
        self.emoji = emoji
        self.author = author
    }
}

/// Message stored without SQLite or materialized integer identifiers.
public struct PortableMessage: Codable, Equatable, Sendable {
    public let id: ArchiveMessageID
    public let date: Date
    public let author: PortableMessageAuthor
    public let messageType: String
    public let text: String?
    public let caption: String?
    public let mediaPath: String?
    public let replyTo: ArchiveMessageID?
    public let replyToPreview: String?
    public let reactions: [PortableReaction]?
    public let warning: String?
    public let seconds: Int?
    public let latitude: Double?
    public let longitude: Double?

    public init(
        id: ArchiveMessageID,
        date: Date,
        author: PortableMessageAuthor,
        messageType: String,
        text: String? = nil,
        caption: String? = nil,
        mediaPath: String? = nil,
        replyTo: ArchiveMessageID? = nil,
        replyToPreview: String? = nil,
        reactions: [PortableReaction]? = nil,
        warning: String? = nil,
        seconds: Int? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil
    ) {
        self.id = id
        self.date = date
        self.author = author
        self.messageType = messageType
        self.text = text
        self.caption = caption
        self.mediaPath = mediaPath
        self.replyTo = replyTo
        self.replyToPreview = replyToPreview
        self.reactions = reactions
        self.warning = warning
        self.seconds = seconds
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// Canonical, versioned conversation document stored as `chat.json`.
public struct PortableConversationDocument: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let conversation: PortableConversationDescriptor
    public let messages: [PortableMessage]
    public let contacts: [PortableContact]

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        conversation: PortableConversationDescriptor,
        messages: [PortableMessage],
        contacts: [PortableContact]
    ) {
        self.schemaVersion = schemaVersion
        self.conversation = conversation
        self.messages = messages
        self.contacts = contacts
    }
}

/// Resource limits enforced before and while reading an archive.
public struct PortableArchiveLimits: Codable, Equatable, Sendable {
    public var maximumArchiveByteCount: Int64
    public var maximumUncompressedByteCount: Int64
    public var maximumEntryByteCount: Int64
    public var maximumJSONByteCount: Int64
    public var maximumEntryCount: Int
    public var maximumCompressionRatio: Double
    public var maximumPathUTF8ByteCount: Int

    public static let `default` = Self(
        maximumArchiveByteCount: 100_000_000_000,
        maximumUncompressedByteCount: 250_000_000_000,
        maximumEntryByteCount: 50_000_000_000,
        maximumJSONByteCount: 2_000_000_000,
        maximumEntryCount: 200_000,
        maximumCompressionRatio: 200,
        maximumPathUTF8ByteCount: 512
    )

    public init(
        maximumArchiveByteCount: Int64,
        maximumUncompressedByteCount: Int64,
        maximumEntryByteCount: Int64,
        maximumJSONByteCount: Int64,
        maximumEntryCount: Int,
        maximumCompressionRatio: Double,
        maximumPathUTF8ByteCount: Int
    ) {
        self.maximumArchiveByteCount = maximumArchiveByteCount
        self.maximumUncompressedByteCount = maximumUncompressedByteCount
        self.maximumEntryByteCount = maximumEntryByteCount
        self.maximumJSONByteCount = maximumJSONByteCount
        self.maximumEntryCount = maximumEntryCount
        self.maximumCompressionRatio = maximumCompressionRatio
        self.maximumPathUTF8ByteCount = maximumPathUTF8ByteCount
    }
}

/// Validated summary of a `.fmcchat` ZIP.
public struct PortableConversationArchiveInfo: Codable, Sendable {
    public let archiveURL: URL
    public let manifest: PortableConversationManifest
    public let archiveByteCount: Int64
    public let uncompressedByteCount: Int64
    public let archiveSHA256: String

    public init(
        archiveURL: URL,
        manifest: PortableConversationManifest,
        archiveByteCount: Int64,
        uncompressedByteCount: Int64,
        archiveSHA256: String
    ) {
        self.archiveURL = archiveURL
        self.manifest = manifest
        self.archiveByteCount = archiveByteCount
        self.uncompressedByteCount = uncompressedByteCount
        self.archiveSHA256 = archiveSHA256
    }
}

/// Errors specific to portable conversation packages.
public enum PortableConversationArchiveError: Error, LocalizedError {
    case invalidSource(reason: String)
    case archiveAlreadyExists(URL)
    case invalidArchive(URL, reason: String)
    case unsupportedSchema(Int)
    case limitExceeded(reason: String)
    case unsafePath(String)
    case integrityMismatch(path: String)
    case invalidDirectory(URL, reason: String)
    case destinationNotEmpty(URL)
    case cancelled
    case fileOperation(URL, underlying: Error)

    public var errorDescription: String? {
        switch self {
        case .invalidSource(let reason):
            return "The portable conversation source is invalid: \(reason)"
        case .archiveAlreadyExists(let url):
            return "A portable conversation archive already exists at \(url.path)."
        case .invalidArchive(let url, let reason):
            return "Invalid portable conversation archive \(url.lastPathComponent): \(reason)"
        case .unsupportedSchema(let version):
            return "Unsupported portable conversation schema version: \(version)."
        case .limitExceeded(let reason):
            return "Portable conversation archive exceeds a safety limit: \(reason)"
        case .unsafePath(let path):
            return "Portable conversation archive contains an unsafe path: \(path)"
        case .integrityMismatch(let path):
            return "Portable conversation file does not match its declared digest: \(path)"
        case .invalidDirectory(let url, let reason):
            return "Invalid portable conversation directory \(url.lastPathComponent): \(reason)"
        case .destinationNotEmpty(let url):
            return "Portable conversation destination is not empty: \(url.path)."
        case .cancelled:
            return "Portable conversation operation was cancelled."
        case .fileOperation(let url, let error):
            return "Portable conversation file operation failed at \(url.path): \(error.localizedDescription)"
        }
    }
}

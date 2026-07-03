//
//  ExtractedWhatsAppBackupInfo.swift
//  SwiftWABackupAPI
//

import Foundation

/// Portable summary generated beside an extracted WhatsApp backup.
public struct ExtractedWhatsAppBackupInfo: Codable, Equatable {
    /// Source iPhone backup metadata that remains useful after extraction.
    public struct Source: Codable, Equatable {
        /// Directory name used by iTunes/Finder to identify the source backup.
        public let iPhoneBackupIdentifier: String

        /// Creation date reported by the source backup's `Status.plist`.
        public let iPhoneBackupCreationDate: Date

        /// Encryption flag declared by the source backup's `Manifest.plist` when available.
        public let isEncrypted: Bool?

        /// iOS backup domain extracted into this copy.
        public let domain: String

        public init(
            iPhoneBackupIdentifier: String,
            iPhoneBackupCreationDate: Date,
            isEncrypted: Bool?,
            domain: String
        ) {
            self.iPhoneBackupIdentifier = iPhoneBackupIdentifier
            self.iPhoneBackupCreationDate = iPhoneBackupCreationDate
            self.isEncrypted = isEncrypted
            self.domain = domain
        }
    }

    /// Counts derived from the source backup manifest.
    public struct ManifestCounts: Codable, Equatable {
        public let totalEntries: Int
        public let files: Int
        public let directories: Int
        public let otherEntries: Int

        public init(totalEntries: Int, files: Int, directories: Int, otherEntries: Int) {
            self.totalEntries = totalEntries
            self.files = files
            self.directories = directories
            self.otherEntries = otherEntries
        }
    }

    /// Counts describing what is present in the extracted copy.
    public struct CopyCounts: Codable, Equatable {
        public let copiedFiles: Int
        public let missingFiles: Int

        public init(copiedFiles: Int, missingFiles: Int) {
            self.copiedFiles = copiedFiles
            self.missingFiles = missingFiles
        }
    }

    /// Counts for media paths stored in `ZWAMEDIAITEM`.
    public struct MediaItemCounts: Codable, Equatable {
        public let total: Int
        public let resolved: Int
        public let missing: Int

        public init(total: Int, resolved: Int, missing: Int) {
            self.total = total
            self.resolved = resolved
            self.missing = missing
        }
    }

    /// Best-effort row counts for known WhatsApp databases and tables.
    public struct DatabaseCounts: Codable, Equatable {
        public let chats: Int?
        public let messages: Int?
        public let supportedMessages: Int?
        public let mediaItems: Int?
        public let contacts: Int?
        public let lidAccounts: Int?
        public let groupMembers: Int?
        public let profilePushNames: Int?

        public init(
            chats: Int?,
            messages: Int?,
            supportedMessages: Int?,
            mediaItems: Int?,
            contacts: Int?,
            lidAccounts: Int?,
            groupMembers: Int?,
            profilePushNames: Int?
        ) {
            self.chats = chats
            self.messages = messages
            self.supportedMessages = supportedMessages
            self.mediaItems = mediaItems
            self.contacts = contacts
            self.lidAccounts = lidAccounts
            self.groupMembers = groupMembers
            self.profilePushNames = profilePushNames
        }
    }

    /// Byte counts for the extracted files and sidecar metadata.
    public struct Sizes: Codable, Equatable {
        public let extractedBytes: Int64
        public let indexBytes: Int64?

        public init(extractedBytes: Int64, indexBytes: Int64?) {
            self.extractedBytes = extractedBytes
            self.indexBytes = indexBytes
        }
    }

    /// Schema version of this JSON document.
    public let schemaVersion: Int

    /// Tool that generated the document.
    public let generator: String

    /// Generation timestamp.
    public let generatedAt: Date

    /// Metadata about the source iPhone backup.
    public let source: Source

    /// Manifest-derived counts.
    public let manifestCounts: ManifestCounts

    /// Extracted-copy counts.
    public let copyCounts: CopyCounts

    /// Media resolution counts.
    public let mediaItemCounts: MediaItemCounts

    /// Best-effort SQLite row counts.
    public let databaseCounts: DatabaseCounts

    /// Extracted-copy sizes.
    public let sizes: Sizes

    /// Non-fatal diagnostics produced while collecting optional information.
    public let warnings: [String]

    public init(
        schemaVersion: Int,
        generator: String,
        generatedAt: Date,
        source: Source,
        manifestCounts: ManifestCounts,
        copyCounts: CopyCounts,
        mediaItemCounts: MediaItemCounts,
        databaseCounts: DatabaseCounts,
        sizes: Sizes,
        warnings: [String]
    ) {
        self.schemaVersion = schemaVersion
        self.generator = generator
        self.generatedAt = generatedAt
        self.source = source
        self.manifestCounts = manifestCounts
        self.copyCounts = copyCounts
        self.mediaItemCounts = mediaItemCounts
        self.databaseCounts = databaseCounts
        self.sizes = sizes
        self.warnings = warnings
    }
}

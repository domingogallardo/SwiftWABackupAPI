import Foundation

/// High-level status reported while inspecting an iPhone backup candidate.
public enum BackupDiscoveryStatus: String, Codable {
    /// The backup contains WhatsApp data and is explicitly marked as not encrypted.
    case ready

    /// The backup contains WhatsApp data but is marked as encrypted.
    case encrypted

    /// The backup contains WhatsApp data, but the encryption flag could not be determined.
    case encryptionStatusUnavailable

    /// One of the required backup files is missing.
    case missingRequiredFile

    /// `Status.plist` exists but does not expose the expected creation date.
    case malformedStatusPlist

    /// The backup structure exists, but the WhatsApp database is not present in `Manifest.db`.
    case missingWhatsAppDatabase

    /// `Manifest.db` could not be opened or queried.
    case unreadableManifestDatabase

    /// The backup candidate could not be read due to an unexpected filesystem or plist error.
    case unreadableBackup
}

/// Diagnostic information returned by `inspectBackups()`.
///
/// Use `status == .ready` before passing `backup` to APIs that assume an
/// unencrypted backup, such as `connectChatStorageDb(from:)`.
public struct BackupDiscoveryInfo: Encodable {
    /// Directory name used by Finder/iTunes to identify the backup.
    public let identifier: String

    /// Absolute backup directory path.
    public let path: String

    /// Creation date reported by `Status.plist` when available.
    public let creationDate: Date?

    /// Encryption flag declared by `Manifest.plist` when available.
    public let isEncrypted: Bool?

    /// Whether the backup is explicitly ready to be used with the chat APIs.
    public let isReady: Bool

    /// High-level inspection result.
    public let status: BackupDiscoveryStatus

    /// Optional diagnostic message for non-ready results.
    public let issue: String?

    private let discoveredBackup: IPhoneBackup?

    /// Resolved backup value that can be passed to the rest of the API.
    ///
    /// Callers should still check `status == .ready` before using it with
    /// APIs that require a verified unencrypted backup.
    public var backup: IPhoneBackup? {
        discoveredBackup
    }

    init(
        identifier: String,
        path: String,
        creationDate: Date?,
        isEncrypted: Bool?,
        status: BackupDiscoveryStatus,
        issue: String?,
        backup: IPhoneBackup? = nil
    ) {
        self.identifier = identifier
        self.path = path
        self.creationDate = creationDate
        self.isEncrypted = isEncrypted
        self.status = status
        self.issue = issue
        self.discoveredBackup = backup
        self.isReady = status == .ready
    }

    private enum CodingKeys: String, CodingKey {
        case identifier
        case path
        case creationDate
        case isEncrypted
        case isReady
        case status
        case issue
    }
}

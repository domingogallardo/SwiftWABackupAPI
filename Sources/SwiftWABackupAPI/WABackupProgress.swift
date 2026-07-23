import Foundation

/// Receives synchronous progress events from long-running backup operations.
public typealias WABackupProgressHandler = (WABackupProgress) -> Void

/// Returns true when a long-running operation should stop cooperatively.
public typealias WABackupCancellationHandler = @Sendable () -> Bool

/// A progress event emitted by public operations that may take noticeable time.
public struct WABackupProgress: Codable, Equatable {
    /// High-level operation currently being performed.
    public enum Phase: String, Codable {
        /// Discovering candidate iPhone backup directories.
        case discoveringIPhoneBackups

        /// Inspecting a single iPhone backup candidate.
        case inspectingIPhoneBackup

        /// Reading WhatsApp entries from `Manifest.db`.
        case loadingManifest

        /// Copying WhatsApp files out of the iPhone backup.
        case copyingBackupFiles

        /// Writing portable sidecar metadata for an extracted backup.
        case writingMetadata

        /// Indexing extracted files in `.wa-backup/index.sqlite`.
        case indexingFiles

        /// Indexing path aliases in `.wa-backup/index.sqlite`.
        case indexingPathAliases

        /// Indexing WhatsApp media rows in `.wa-backup/index.sqlite`.
        case indexingMediaItems

        /// Calculating `.wa-backup/backup-info.json`.
        case calculatingBackupInfo

        /// Loading chat summaries.
        case loadingChats

        /// Exporting a chat payload.
        case exportingChat

        /// Loading messages for a chat.
        case loadingMessages

        /// Processing chat messages.
        case processingMessages

        /// Building the contact list for a chat export.
        case buildingContacts

        /// Copying message media, profile photos, or contact photos.
        case exportingMedia

        /// Validating local conversation composition sources.
        case validatingConversationSources

        /// Hashing media referenced by conversation composition sources.
        case hashingConversationMedia

        /// Converting source messages into exact canonical keys.
        case canonicalizingConversationMessages

        /// Resolving relationships between source-relative users.
        case inferringConversationPerspectives

        /// Finding ordered content anchors between conversation sources.
        case aligningConversationMessages

        /// Grouping message occurrences and calculating source impacts.
        case classifyingConversationComposition

        /// Building a self-contained materialized conversation.
        case materializingConversation

        /// Copying deduplicated media into a materialized conversation.
        case copyingConversationMedia

        /// Creating a portable `.fmcchat` package.
        case creatingPortableConversationArchive

        /// Inspecting and validating a portable `.fmcchat` package.
        case inspectingPortableConversationArchive

        /// Extracting a validated portable conversation package.
        case extractingPortableConversationArchive

        /// The public operation completed successfully.
        case completed
    }

    /// Kind of work represented by the unit counters.
    public enum Unit: String, Codable {
        case backups
        case manifestEntries
        case files
        case metadataRows
        case mediaItems
        case chats
        case messages
        case contacts
        case mediaFiles
        case sources
        case anchors
        case archiveEntries
        case bytes
        case phases
    }

    /// High-level operation currently being performed.
    public let phase: Phase

    /// Number of completed units for this phase.
    public let completedUnitCount: Int

    /// Total unit count when it is known. A nil value means indeterminate progress.
    public let totalUnitCount: Int?

    /// Kind of work represented by `completedUnitCount` and `totalUnitCount`.
    public let unit: Unit?

    /// Optional current file, chat, message, path, or status label.
    public let currentItem: String?

    /// Creates a progress event.
    public init(
        phase: Phase,
        completedUnitCount: Int,
        totalUnitCount: Int? = nil,
        unit: Unit? = nil,
        currentItem: String? = nil
    ) {
        self.phase = phase
        self.completedUnitCount = completedUnitCount
        self.totalUnitCount = totalUnitCount
        self.unit = unit
        self.currentItem = currentItem
    }

    /// Fraction completed in the range 0...1 when `totalUnitCount` is known and positive.
    public var fractionCompleted: Double? {
        guard let totalUnitCount, totalUnitCount > 0 else {
            return nil
        }

        return min(max(Double(completedUnitCount) / Double(totalUnitCount), 0), 1)
    }

    /// Whether this event should be represented as indeterminate progress.
    public var isIndeterminate: Bool {
        totalUnitCount == nil || totalUnitCount == 0
    }
}

func reportProgress(
    _ progress: WABackupProgressHandler?,
    phase: WABackupProgress.Phase,
    completedUnitCount: Int,
    totalUnitCount: Int? = nil,
    unit: WABackupProgress.Unit? = nil,
    currentItem: String? = nil
) {
    progress?(
        WABackupProgress(
            phase: phase,
            completedUnitCount: completedUnitCount,
            totalUnitCount: totalUnitCount,
            unit: unit,
            currentItem: currentItem
        )
    )
}

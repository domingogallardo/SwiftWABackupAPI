import Foundation

/// Stable client-provided identifier for one input of a conversation composition.
public struct ConversationSourceID: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

/// Identifier that remains independent from WhatsApp and materialized integer primary keys.
public struct ArchiveMessageID: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.rawValue = try container.decode(UUID.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// Kind of payload wrapped by a conversation source.
public enum ConversationSourceKind: String, Codable, Sendable {
    case exportedDocument
    case portableDocument
}

/// One canonical address that can identify a WhatsApp participant.
public struct ParticipantAddress: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case phone
        case phoneJID
        case lidJID
    }

    public let kind: Kind
    public let value: String

    public init(kind: Kind, value: String) {
        self.kind = kind
        self.value = value
    }
}

/// A participant identity expressed only through canonical addresses, never display names.
public struct CanonicalParticipantIdentity: Codable, Hashable, Sendable {
    /// Sorted, normalized and duplicate-free participant addresses.
    public let addresses: [ParticipantAddress]

    public init(addresses: [ParticipantAddress]) {
        self.addresses = Self.normalized(addresses)
    }

    var comparisonKeys: Set<String> {
        Set(addresses.compactMap(Self.comparisonKey))
    }

    var preferredComparisonKey: String? {
        let keys = comparisonKeys
        return keys.filter { $0.hasPrefix("phone:") }.sorted().first
            ?? keys.filter { $0.hasPrefix("lid:") }.sorted().first
    }

    private static func normalized(_ addresses: [ParticipantAddress]) -> [ParticipantAddress] {
        let normalized = addresses.compactMap { address -> ParticipantAddress? in
            switch address.kind {
            case .phone:
                let digits = address.value.filter(\.isNumber)
                return digits.isEmpty ? nil : ParticipantAddress(kind: .phone, value: digits)
            case .phoneJID:
                let jid = address.value
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .precomposedStringWithCanonicalMapping
                    .lowercased()
                guard jid.hasSuffix("@s.whatsapp.net") else { return nil }
                let user = String(jid.prefix { $0 != "@" }).filter(\.isNumber)
                guard !user.isEmpty else { return nil }
                return ParticipantAddress(kind: .phoneJID, value: "\(user)@s.whatsapp.net")
            case .lidJID:
                let jid = address.value
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .precomposedStringWithCanonicalMapping
                    .lowercased()
                guard jid.hasSuffix("@lid"), jid.first != "@" else { return nil }
                return ParticipantAddress(kind: .lidJID, value: jid)
            }
        }

        return Array(Set(normalized)).sorted {
            if $0.kind.rawValue != $1.kind.rawValue {
                return $0.kind.rawValue < $1.kind.rawValue
            }
            return $0.value < $1.value
        }
    }

    private static func comparisonKey(_ address: ParticipantAddress) -> String? {
        switch address.kind {
        case .phone:
            return "phone:\(address.value)"
        case .phoneJID:
            let digits = String(address.value.prefix { $0 != "@" }).filter(\.isNumber)
            return digits.isEmpty ? nil : "phone:\(digits)"
        case .lidJID:
            return "lid:\(address.value)"
        }
    }
}

/// Confidence attached to a perspective identity supplied by a client.
public enum HintConfidence: String, Codable, Sendable {
    case derived
    case asserted
}

/// Optional identity hint for the user represented by `isFromMe` in one source.
public struct ConversationPerspectiveHint: Codable, Hashable, Sendable {
    public let participant: CanonicalParticipantIdentity
    public let confidence: HintConfidence

    public init(participant: CanonicalParticipantIdentity, confidence: HintConfidence) {
        self.participant = participant
        self.confidence = confidence
    }
}

/// A validated, opaque input to conversation composition.
public struct ConversationSource {
    public let id: ConversationSourceID
    public let kind: ConversationSourceKind
    public let conversationIdentityHint: CanonicalParticipantIdentity?
    public let perspectiveHint: ConversationPerspectiveHint?
    public let sourceDate: Date

    let document: ExportedChatDocument
    let mediaDirectoryURL: URL
    let stableMessageIDs: [Int: ArchiveMessageID]

    public init(
        id: ConversationSourceID,
        document: ExportedChatDocument,
        mediaDirectoryURL: URL,
        conversationIdentityHint: CanonicalParticipantIdentity? = nil,
        perspectiveHint: ConversationPerspectiveHint? = nil,
        stableMessageIDs: [Int: ArchiveMessageID] = [:]
    ) throws {
        guard !id.rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ConversationCompositionError.invalidSource(
                sourceID: id,
                reason: "The source identifier is empty."
            )
        }
        guard document.schemaVersion == ExportedChatDocument.currentSchemaVersion else {
            throw ConversationCompositionError.invalidSource(
                sourceID: id,
                reason: "The exported chat schema is unsupported."
            )
        }
        if let conversationIdentityHint, conversationIdentityHint.addresses.isEmpty {
            throw ConversationCompositionError.invalidSource(
                sourceID: id,
                reason: "The conversation identity hint has no valid addresses."
            )
        }
        if let perspectiveHint, perspectiveHint.participant.addresses.isEmpty {
            throw ConversationCompositionError.invalidSource(
                sourceID: id,
                reason: "The perspective hint has no valid addresses."
            )
        }

        self.id = id
        self.kind = .exportedDocument
        self.conversationIdentityHint = conversationIdentityHint
        self.perspectiveHint = perspectiveHint
        self.sourceDate = document.exportedAt
        self.document = document
        self.mediaDirectoryURL = mediaDirectoryURL.standardizedFileURL
        self.stableMessageIDs = stableMessageIDs
    }

    public init(
        id: ConversationSourceID,
        exportedChat: ExportedChat,
        conversationIdentityHint: CanonicalParticipantIdentity? = nil,
        perspectiveHint: ConversationPerspectiveHint? = nil,
        stableMessageIDs: [Int: ArchiveMessageID] = [:]
    ) throws {
        try self.init(
            id: id,
            document: exportedChat.document,
            mediaDirectoryURL: exportedChat.mediaDirectoryURL,
            conversationIdentityHint: conversationIdentityHint,
            perspectiveHint: perspectiveHint,
            stableMessageIDs: stableMessageIDs
        )
    }
}

/// Relationship between the source-relative users of one or more inputs.
public struct ConversationPerspectiveConstraint: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case samePerspective
        case differentPerspectives
        case sourceIdentity
    }

    public let kind: Kind
    public let sourceIDs: [ConversationSourceID]
    public let participant: CanonicalParticipantIdentity?

    private init(
        kind: Kind,
        sourceIDs: [ConversationSourceID],
        participant: CanonicalParticipantIdentity?
    ) {
        self.kind = kind
        self.sourceIDs = sourceIDs
        self.participant = participant
    }

    public static func samePerspective(sourceIDs: [ConversationSourceID]) -> Self {
        Self(kind: .samePerspective, sourceIDs: sourceIDs, participant: nil)
    }

    public static func differentPerspectives(
        _ first: ConversationSourceID,
        _ second: ConversationSourceID
    ) -> Self {
        Self(kind: .differentPerspectives, sourceIDs: [first, second], participant: nil)
    }

    public static func identity(
        _ participant: CanonicalParticipantIdentity,
        for sourceID: ConversationSourceID
    ) -> Self {
        Self(kind: .sourceIdentity, sourceIDs: [sourceID], participant: participant)
    }
}

/// Algorithm family used for a composition.
public struct ConversationCompositionPolicy: Codable, Sendable {
    public enum Profile: String, Codable, Sendable {
        case currentUnifiedView
        case conservativeCrossPerspective
    }

    public let profile: Profile
    public let maximumTimestampDifferenceMilliseconds: Int64
    public let minimumStrongAnchorCount: Int
    public let minimumMatchedWindowCount: Int
    public let minimumOverlapMessageCount: Int
    public let minimumOrderConsistency: Double
    public let maximumUnresolvedAuthorFraction: Double
    public let requireOrientableExclusiveMessages: Bool
    public let allowSystematicTimestampOffset: Bool

    public static let currentUnifiedView = Self(profile: .currentUnifiedView)

    /// Conservative policy for read-only analysis across source perspectives.
    public static let conservativeDefault = Self(profile: .conservativeCrossPerspective)

    public init(profile: Profile) {
        self.init(
            profile: profile,
            maximumTimestampDifferenceMilliseconds: 2_000,
            minimumStrongAnchorCount: profile == .currentUnifiedView ? 0 : 3,
            minimumMatchedWindowCount: 0,
            minimumOverlapMessageCount: profile == .currentUnifiedView ? 0 : 3,
            minimumOrderConsistency: 0.9,
            maximumUnresolvedAuthorFraction: 0.1,
            requireOrientableExclusiveMessages: true,
            allowSystematicTimestampOffset: false
        )
    }

    public init(
        profile: Profile,
        maximumTimestampDifferenceMilliseconds: Int64,
        minimumStrongAnchorCount: Int,
        minimumMatchedWindowCount: Int = 0,
        minimumOverlapMessageCount: Int,
        minimumOrderConsistency: Double,
        maximumUnresolvedAuthorFraction: Double = 0.1,
        requireOrientableExclusiveMessages: Bool = true,
        allowSystematicTimestampOffset: Bool = false
    ) {
        self.profile = profile
        self.maximumTimestampDifferenceMilliseconds = max(0, maximumTimestampDifferenceMilliseconds)
        self.minimumStrongAnchorCount = max(0, minimumStrongAnchorCount)
        self.minimumMatchedWindowCount = max(0, minimumMatchedWindowCount)
        self.minimumOverlapMessageCount = max(0, minimumOverlapMessageCount)
        self.minimumOrderConsistency = min(max(minimumOrderConsistency, 0), 1)
        self.maximumUnresolvedAuthorFraction = min(max(maximumUnresolvedAuthorFraction, 0), 1)
        self.requireOrientableExclusiveMessages = requireOrientableExclusiveMessages
        self.allowSystematicTimestampOffset = allowSystematicTimestampOffset
    }
}

/// Digest of one validated composition source.
public struct ConversationSourceDigest: Codable, Equatable, Sendable {
    public let sourceID: ConversationSourceID
    public let documentDigest: String
    public let mediaDigest: String

    public init(sourceID: ConversationSourceID, documentDigest: String, mediaDigest: String) {
        self.sourceID = sourceID
        self.documentDigest = documentDigest
        self.mediaDigest = mediaDigest
    }
}

/// Confidence assigned to an analyzed composition plan.
public enum ConversationCompositionConfidence: String, Codable, Sendable {
    case low
    case medium
    case high
}

/// Whether a composition plan can be materialized.
public enum ConversationCompositionDisposition: String, Codable, Sendable {
    case applicable
    case requiresReview
    case rejected
}

/// Non-sensitive diagnostic reasons produced while analyzing a composition.
public enum CompositionReason: String, Codable, Sendable {
    case samePerspectiveConstraintAccepted
    case duplicateFingerprintWithinSource
    case inconsistentReplyMetadata
    case groupJIDMatched
    case groupJIDMismatch
    case strongContentOverlap
    case insufficientContentOverlap
    case orderedAnchorsAccepted
    case inconsistentAnchorOrder
    case samePerspectiveInferred
    case differentPerspectiveInferred
    case perspectiveConstraintAccepted
    case perspectiveHintAccepted
    case perspectiveEvidenceConflict
    case perspectiveUnresolved
    case individualConversationInferredFromOverlap
    case exclusiveMessagesNotOrientable
    case unresolvedGroupAuthors
    case systematicTimestampOffsetApplied
    case incompatibleStableMessageID
}

/// Global occurrence and logical-message statistics for a composition.
public struct ConversationCompositionStatistics: Codable, Equatable, Sendable {
    /// Number of input sources.
    public let sourceCount: Int
    /// Total message occurrences across all source documents.
    public let inputMessageCount: Int
    /// Number of logical messages after exact deduplication.
    public let materializedMessageCount: Int
    /// Number of input occurrences removed by deduplication.
    public let deduplicatedOccurrenceCount: Int
    /// Logical messages represented in at least two sources.
    public let sharedLogicalMessageCount: Int
    /// Logical messages represented in exactly one source.
    public let exclusiveLogicalMessageCount: Int
    /// Bytes of referenced input media, counted once per source file.
    public let inputMediaByteCount: Int64
    /// Bytes of unique message media in the materialized conversation.
    public let materializedMediaByteCount: Int64
    /// Input media bytes avoided through content deduplication.
    public let duplicateMediaByteCount: Int64
}

/// Contribution made by one source to the logical conversation.
public struct ConversationSourceImpact: Codable, Equatable, Sendable {
    public let sourceID: ConversationSourceID
    public let sourceMessageCount: Int
    public let exclusiveMessageCount: Int
    public let sharedMessageCount: Int
    public let exclusiveMediaByteCount: Int64
}

/// Effect of rebuilding a composition without one source.
public struct ConversationRemovalImpact: Codable, Equatable, Sendable {
    public let sourceID: ConversationSourceID
    public let currentMessageCount: Int
    public let sourceMessageCount: Int
    public let removedMessageCount: Int
    public let resultingMessageCount: Int
    public let removedMediaByteCount: Int64
}

/// Serializable result of analyzing sources without writing output.
public struct ConversationCompositionPlan: Codable, Sendable {
    public let schemaVersion: Int
    public let algorithmVersion: Int
    public let profile: ConversationCompositionPolicy.Profile
    public let targetSourceID: ConversationSourceID
    public let sourceDigests: [ConversationSourceDigest]
    public let statistics: ConversationCompositionStatistics
    public let sourceImpacts: [ConversationSourceImpact]
    public let confidence: ConversationCompositionConfidence
    public let disposition: ConversationCompositionDisposition
    public let reasons: [CompositionReason]
    /// Evidence used when this plan was prepared from source-relative users
    /// whose perspectives may differ. It is nil for the current unified view.
    public let crossPerspectiveDiagnostic: ConversationCompositionDiagnostic?

    /// Returns the logical effect of rebuilding without one source.
    public func removalImpact(of sourceID: ConversationSourceID) throws -> ConversationRemovalImpact {
        guard let impact = sourceImpacts.first(where: { $0.sourceID == sourceID }) else {
            throw ConversationCompositionError.invalidSource(
                sourceID: sourceID,
                reason: "The source is not part of this composition plan."
            )
        }
        return ConversationRemovalImpact(
            sourceID: sourceID,
            currentMessageCount: statistics.materializedMessageCount,
            sourceMessageCount: impact.sourceMessageCount,
            removedMessageCount: impact.exclusiveMessageCount,
            resultingMessageCount: statistics.materializedMessageCount - impact.exclusiveMessageCount,
            removedMediaByteCount: impact.exclusiveMediaByteCount
        )
    }
}

/// Opaque analyzed composition that can later be materialized safely.
public struct PreparedConversationComposition {
    public let plan: ConversationCompositionPlan

    let storage: ConversationPreparationStorage

    init(plan: ConversationCompositionPlan, storage: ConversationPreparationStorage) {
        self.plan = plan
        self.storage = storage
    }
}

/// Stable-message mapping for one source.
public struct ConversationSourceMapping: Codable, Sendable {
    public let sourceID: ConversationSourceID
    public let sourceMessageIDs: [Int: ArchiveMessageID]
}

/// Statistics specific to writing a materialized directory.
public struct ConversationMaterializationStatistics: Codable, Equatable, Sendable {
    public let messageCount: Int
    public let copiedMediaFileCount: Int
    public let copiedMediaByteCount: Int64
}

/// A complete and validated `chat.json` plus `Media` staging result.
public struct ConversationMaterializationResult {
    public let document: ExportedChatDocument
    public let directoryURL: URL
    public let documentURL: URL
    public let mediaDirectoryURL: URL
    public let stableMessageIDsByMaterializedID: [Int: ArchiveMessageID]
    public let sourceMappings: [ConversationSourceMapping]
    public let sourceImpacts: [ConversationSourceImpact]
    public let statistics: ConversationMaterializationStatistics
}

/// Errors raised while analyzing or materializing local conversation sources.
public enum ConversationCompositionError: Error, LocalizedError {
    case noSources
    case duplicateSourceID(ConversationSourceID)
    case targetSourceNotFound(ConversationSourceID)
    case invalidSource(sourceID: ConversationSourceID, reason: String)
    case unsupportedCompositionProfile
    case missingSamePerspectiveConstraint([ConversationSourceID])
    case invalidPerspectiveConstraint(reason: String)
    case differentConversations(reason: String)
    case ambiguousConversationIdentity(reason: String)
    case crossPerspectiveCompositionRejected(ConversationCompositionDiagnostic)
    case crossPerspectiveCompositionRequiresReview(ConversationCompositionDiagnostic)
    case incompatibleStableMessageID(ArchiveMessageID)
    case inputChanged(sourceID: ConversationSourceID)
    case destinationNotEmpty(URL)
    case cancelled
    case fileOperation(url: URL, underlying: Error)
    case invalidMaterializedOutput(url: URL, reason: String)

    public var errorDescription: String? {
        switch self {
        case .noSources:
            return "Conversation composition requires at least one source."
        case .duplicateSourceID(let sourceID):
            return "Conversation source identifier is duplicated: \(sourceID.rawValue)."
        case .targetSourceNotFound(let sourceID):
            return "The target conversation source was not found: \(sourceID.rawValue)."
        case .invalidSource(let sourceID, let reason):
            return "Invalid conversation source \(sourceID.rawValue): \(reason)"
        case .unsupportedCompositionProfile:
            return "The requested conversation composition profile is not implemented."
        case .missingSamePerspectiveConstraint:
            return "The current unified-view profile requires one same-perspective constraint covering every source."
        case .invalidPerspectiveConstraint(let reason):
            return "Invalid conversation perspective constraint: \(reason)"
        case .differentConversations(let reason):
            return "The sources do not represent the same conversation: \(reason)"
        case .ambiguousConversationIdentity(let reason):
            return "The conversation identity could not be resolved safely: \(reason)"
        case .crossPerspectiveCompositionRejected:
            return "Cross-perspective conversation composition was rejected by the conservative diagnostic."
        case .crossPerspectiveCompositionRequiresReview:
            return "Cross-perspective conversation composition requires explicit review before materialization."
        case .incompatibleStableMessageID(let messageID):
            return "Stable message identifier is assigned to incompatible messages: \(messageID.rawValue)."
        case .inputChanged(let sourceID):
            return "Conversation source changed after analysis: \(sourceID.rawValue)."
        case .destinationNotEmpty(let url):
            return "Conversation materialization destination is not empty: \(url.path)."
        case .cancelled:
            return "Conversation composition was cancelled."
        case .fileOperation(let url, let error):
            return "Conversation file operation failed at \(url.path): \(error.localizedDescription)"
        case .invalidMaterializedOutput(let url, let reason):
            return "Invalid materialized conversation at \(url.path): \(reason)"
        }
    }
}

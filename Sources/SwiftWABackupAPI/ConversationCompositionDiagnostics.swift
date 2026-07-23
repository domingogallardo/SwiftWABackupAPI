import Foundation

/// Relationship between one source-relative user and the selected target source.
public enum PerspectiveRelationship: String, Codable, Sendable {
    case sameAsTarget
    case differentFromTarget
    case unresolved
    case conflicting
}

/// Evidence-backed perspective resolution for one composition source.
public struct SourcePerspectiveResolution: Codable, Sendable {
    public let sourceID: ConversationSourceID
    public let inferredParticipant: CanonicalParticipantIdentity?
    public let relationToTarget: PerspectiveRelationship
    public let evidenceCount: Int
    public let confidence: ConversationCompositionConfidence
    public let reasons: [CompositionReason]
}

/// Semantic relationship between all analyzed conversation sources.
public enum ConversationEquivalenceStatus: String, Codable, Sendable {
    case same
    case different
    case ambiguous
}

/// Conversation identity result. Display names and local database IDs never participate.
public struct ConversationEquivalence: Codable, Sendable {
    public let chatType: ChatInfo.ChatType
    public let status: ConversationEquivalenceStatus
    public let normalizedGroupJID: String?
    public let perspectiveResolutions: [SourcePerspectiveResolution]
    public let reasons: [CompositionReason]
}

/// Privacy-safe alignment measurements for one source compared with the target.
public struct ConversationPairAlignmentStatistics: Codable, Equatable, Sendable {
    public let sourceID: ConversationSourceID
    public let candidateCount: Int
    public let strongAnchorCount: Int
    public let matchedMessageCount: Int
    public let targetMessageCount: Int
    public let sourceMessageCount: Int
    public let targetCoverage: Double
    public let sourceCoverage: Double
    public let orderConsistency: Double
    public let minimumTimestampDifferenceMilliseconds: Int64?
    public let maximumTimestampDifferenceMilliseconds: Int64?
    public let medianTimestampDifferenceMilliseconds: Int64?
    public let percentile95TimestampDifferenceMilliseconds: Int64?
}

/// Aggregate measurements from a read-only cross-perspective diagnosis.
public struct ConversationDiagnosticStatistics: Codable, Equatable, Sendable {
    public let sourceCount: Int
    public let inputMessageCount: Int
    public let matchedMessageCount: Int
    public let exclusiveMessageCount: Int
    public let strongAnchorCount: Int
    public let resolvedAuthorCount: Int
    public let unresolvedAuthorCount: Int
    public let unorientableExclusiveMessageCount: Int
    public let conflictingPerspectiveCount: Int
    public let unresolvedPerspectiveCount: Int
}

/// Serializable, content-free report produced before cross-perspective materialization exists.
public struct ConversationCompositionDiagnostic: Codable, Sendable {
    public let schemaVersion: Int
    public let algorithmVersion: Int
    public let profile: ConversationCompositionPolicy.Profile
    public let targetSourceID: ConversationSourceID
    public let sourceDigests: [ConversationSourceDigest]
    public let equivalence: ConversationEquivalence
    public let perspectives: [SourcePerspectiveResolution]
    public let pairAlignments: [ConversationPairAlignmentStatistics]
    public let statistics: ConversationDiagnosticStatistics
    public let confidence: ConversationCompositionConfidence
    public let disposition: ConversationCompositionDisposition
    public let reasons: [CompositionReason]

    /// Copy suitable for logs and CLI output. Participant and group identifiers
    /// are intentionally removed while counts, hashes and decisions remain.
    public var privacySafeReport: Self {
        let redactedPerspectives = perspectives.map {
            SourcePerspectiveResolution(
                sourceID: $0.sourceID,
                inferredParticipant: nil,
                relationToTarget: $0.relationToTarget,
                evidenceCount: $0.evidenceCount,
                confidence: $0.confidence,
                reasons: $0.reasons
            )
        }
        return Self(
            schemaVersion: schemaVersion,
            algorithmVersion: algorithmVersion,
            profile: profile,
            targetSourceID: targetSourceID,
            sourceDigests: sourceDigests,
            equivalence: ConversationEquivalence(
                chatType: equivalence.chatType,
                status: equivalence.status,
                normalizedGroupJID: nil,
                perspectiveResolutions: redactedPerspectives,
                reasons: equivalence.reasons
            ),
            perspectives: redactedPerspectives,
            pairAlignments: pairAlignments,
            statistics: statistics,
            confidence: confidence,
            disposition: disposition,
            reasons: reasons
        )
    }
}

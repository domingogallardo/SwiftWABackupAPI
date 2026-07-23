import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

private struct ConversationSourceMediaKey: Hashable {
    let sourceID: ConversationSourceID
    let filename: String
}

private struct CanonicalConversationMedia: Codable, Hashable {
    let sha256: String
    let byteCount: Int64
}

private struct ConversationMediaRecord: Equatable {
    let key: ConversationSourceMediaKey
    let url: URL
    let identity: CanonicalConversationMedia
    let modificationDate: Date
}

private struct AnalyzedConversationSource {
    let source: ConversationSource
    let documentDigest: String
    let mediaDigest: String
    let mediaByFilename: [String: ConversationMediaRecord]
}

private struct ConversationSourceMessageKey: Hashable {
    let sourceID: ConversationSourceID
    let messageID: Int
}

private struct CanonicalConversationMessagePayload: Encodable {
    let timestampMilliseconds: Int64
    let author: String
    let messageType: String
    let text: String?
    let caption: String?
    let media: CanonicalConversationMedia?
    let seconds: Int?
    let latitude: Double?
    let longitude: Double?
}

private struct AnalyzedConversationMessage {
    let sourceIndex: Int
    let messageIndex: Int
    let sourceID: ConversationSourceID
    let message: MessageInfo
    let materializationMessage: MessageInfo
    let fingerprint: String
    let mediaRecord: ConversationMediaRecord?

    var key: ConversationSourceMessageKey {
        ConversationSourceMessageKey(sourceID: sourceID, messageID: message.id)
    }
}

private struct LogicalConversationMessage {
    let fingerprint: String
    var references: [AnalyzedConversationMessage]
    var stableID: ArchiveMessageID

    var representative: AnalyzedConversationMessage {
        references[0]
    }
}

private enum DiagnosticRelativeAuthor {
    case sourceUser
    case participant(Set<String>)
    case unresolved

    var isResolved: Bool {
        if case .unresolved = self { return false }
        return true
    }
}

private struct DiagnosticMessageCore: Encodable {
    let messageType: String
    let text: String?
    let caption: String?
    let media: CanonicalConversationMedia?
    let seconds: Int?
    let latitude: Double?
    let longitude: Double?
}

private struct DiagnosticMessage {
    let index: Int
    let message: MessageInfo
    let coreSignature: String
    let isStrong: Bool
    let author: DiagnosticRelativeAuthor
    let stableID: ArchiveMessageID?
}

private struct DiagnosticSource {
    let analyzed: AnalyzedConversationSource
    let messages: [DiagnosticMessage]
}

private struct DiagnosticAnchor {
    let targetIndex: Int
    let sourceIndex: Int
    let timestampDifferenceMilliseconds: Int64
}

private struct DiagnosticPairResult {
    let sourceID: ConversationSourceID
    let anchors: [DiagnosticAnchor]
    let candidateCount: Int
    let relationship: PerspectiveRelationship
    let relationshipEvidenceCount: Int
    let relationshipReasons: Set<CompositionReason>
    let statistics: ConversationPairAlignmentStatistics
    let matchedTargetIndices: Set<Int>
    let matchedSourceIndices: Set<Int>
    let targetUserIdentityKeys: Set<String>
    let sourceUserIdentityKeys: Set<String>
    let estimatedTimestampOffsetMilliseconds: Int64
}

private struct CrossPerspectiveDiagnosticAnalysis {
    let sources: [DiagnosticSource]
    let target: DiagnosticSource
    let pairResults: [DiagnosticPairResult]
    let diagnostic: ConversationCompositionDiagnostic
}

private struct ConversationOccurrenceUnionFind {
    private var parents: [Int]

    init(count: Int) {
        parents = Array(0..<count)
    }

    mutating func root(of value: Int) -> Int {
        var current = value
        while parents[current] != current {
            current = parents[current]
        }
        var cursor = value
        while parents[cursor] != cursor {
            let next = parents[cursor]
            parents[cursor] = current
            cursor = next
        }
        return current
    }

    mutating func join(_ lhs: Int, _ rhs: Int) {
        let lhsRoot = root(of: lhs)
        let rhsRoot = root(of: rhs)
        if lhsRoot != rhsRoot {
            parents[rhsRoot] = lhsRoot
        }
    }
}

private struct TargetOrientedMessage {
    let message: MessageInfo
    let canonicalAuthor: String
}

private struct TargetAuthorResolution {
    let isFromMe: Bool
    let author: MessageAuthor?
    let canonicalAuthor: String
}

private struct DiagnosticConstraintResolution {
    let relationship: PerspectiveRelationship?
    let reasons: Set<CompositionReason>
}

struct ConversationPreparationStorage {
    fileprivate let analyzedSources: [AnalyzedConversationSource]
    fileprivate let logicalMessages: [LogicalConversationMessage]
    fileprivate let groupIndexBySourceMessage: [ConversationSourceMessageKey: Int]
}

/// Analyzes and materializes same-perspective or conservatively aligned
/// cross-perspective conversation compositions.
public struct ConversationCompositionEngine {
    public let policy: ConversationCompositionPolicy

    public init(policy: ConversationCompositionPolicy = .currentUnifiedView) {
        self.policy = policy
    }

    /// Validates and groups N exported documents without writing output.
    public func analyze(
        sources: [ConversationSource],
        targetSourceID: ConversationSourceID,
        perspectiveConstraints: [ConversationPerspectiveConstraint],
        progress: WABackupProgressHandler? = nil,
        cancellation: WABackupCancellationHandler? = nil
    ) throws -> PreparedConversationComposition {
        try analyze(
            sources: sources,
            targetSourceID: targetSourceID,
            perspectiveConstraints: perspectiveConstraints,
            progress: progress,
            cancellation: cancellation,
            reportsCompletion: true
        )
    }

    /// Writes one analyzed composition as a validated `chat.json` and `Media` directory.
    public func materialize(
        _ preparation: PreparedConversationComposition,
        targetChatID: Int,
        destinationDirectory: URL,
        progress: WABackupProgressHandler? = nil,
        cancellation: WABackupCancellationHandler? = nil
    ) throws -> ConversationMaterializationResult {
        try materialize(
            preparation,
            targetChatID: targetChatID,
            destinationDirectory: destinationDirectory,
            progress: progress,
            cancellation: cancellation,
            reportsCompletion: true,
            reportsValidationProgress: true
        )
    }

    /// Analyzes and materializes using the same implementation as the two-step API.
    public func compose(
        sources: [ConversationSource],
        targetSourceID: ConversationSourceID,
        perspectiveConstraints: [ConversationPerspectiveConstraint],
        targetChatID: Int,
        destinationDirectory: URL,
        progress: WABackupProgressHandler? = nil,
        cancellation: WABackupCancellationHandler? = nil
    ) throws -> ConversationMaterializationResult {
        let preparation = try analyze(
            sources: sources,
            targetSourceID: targetSourceID,
            perspectiveConstraints: perspectiveConstraints,
            progress: progress,
            cancellation: cancellation,
            reportsCompletion: false
        )
        let result = try materialize(
            preparation,
            targetChatID: targetChatID,
            destinationDirectory: destinationDirectory,
            progress: progress,
            cancellation: cancellation,
            reportsCompletion: false,
            reportsValidationProgress: false
        )
        reportProgress(
            progress,
            phase: .completed,
            completedUnitCount: 1,
            totalUnitCount: 1,
            unit: .phases
        )
        return result
    }

    /// Produces a privacy-safe, read-only diagnosis for sources whose relative
    /// perspectives may differ. A rejected composition is returned as data.
    public func diagnose(
        sources: [ConversationSource],
        targetSourceID: ConversationSourceID,
        perspectiveConstraints: [ConversationPerspectiveConstraint] = [],
        progress: WABackupProgressHandler? = nil,
        cancellation: WABackupCancellationHandler? = nil
    ) throws -> ConversationCompositionDiagnostic {
        try diagnoseCrossPerspective(
            sources: sources,
            targetSourceID: targetSourceID,
            perspectiveConstraints: perspectiveConstraints,
            progress: progress,
            cancellation: cancellation,
            reportsCompletion: true
        ).diagnostic
    }
}

private extension ConversationCompositionEngine {
    func analyze(
        sources: [ConversationSource],
        targetSourceID: ConversationSourceID,
        perspectiveConstraints: [ConversationPerspectiveConstraint],
        progress: WABackupProgressHandler?,
        cancellation: WABackupCancellationHandler?,
        reportsCompletion: Bool
    ) throws -> PreparedConversationComposition {
        switch policy.profile {
        case .currentUnifiedView:
            return try analyzeCurrentUnifiedView(
                sources: sources,
                targetSourceID: targetSourceID,
                perspectiveConstraints: perspectiveConstraints,
                progress: progress,
                cancellation: cancellation,
                reportsCompletion: reportsCompletion
            )
        case .conservativeCrossPerspective:
            return try analyzeCrossPerspective(
                sources: sources,
                targetSourceID: targetSourceID,
                perspectiveConstraints: perspectiveConstraints,
                progress: progress,
                cancellation: cancellation,
                reportsCompletion: reportsCompletion
            )
        }
    }

    func analyzeCurrentUnifiedView(
        sources: [ConversationSource],
        targetSourceID: ConversationSourceID,
        perspectiveConstraints: [ConversationPerspectiveConstraint],
        progress: WABackupProgressHandler?,
        cancellation: WABackupCancellationHandler?,
        reportsCompletion: Bool
    ) throws -> PreparedConversationComposition {
        guard !sources.isEmpty else {
            throw ConversationCompositionError.noSources
        }

        try checkCancellation(cancellation)
        var seenSourceIDs = Set<ConversationSourceID>()
        for source in sources where !seenSourceIDs.insert(source.id).inserted {
            throw ConversationCompositionError.duplicateSourceID(source.id)
        }
        guard sources.contains(where: { $0.id == targetSourceID }) else {
            throw ConversationCompositionError.targetSourceNotFound(targetSourceID)
        }
        try validateSamePerspectiveConstraint(
            perspectiveConstraints,
            expectedSourceIDs: seenSourceIDs
        )

        let referencedMediaCount = sources.reduce(0) {
            $0 + Set(referencedFilenames(in: $1.document)).count
        }
        var hashedMediaCount = 0
        var analyzedSources: [AnalyzedConversationSource] = []
        analyzedSources.reserveCapacity(sources.count)

        for (index, source) in sources.enumerated() {
            try checkCancellation(cancellation)
            reportProgress(
                progress,
                phase: .validatingConversationSources,
                completedUnitCount: index,
                totalUnitCount: sources.count,
                unit: .sources
            )
            let analyzed = try analyzeSource(
                source,
                cancellation: cancellation,
                didHashMedia: {
                    hashedMediaCount += 1
                    reportProgress(
                        progress,
                        phase: .hashingConversationMedia,
                        completedUnitCount: hashedMediaCount,
                        totalUnitCount: referencedMediaCount,
                        unit: .mediaFiles
                    )
                }
            )
            analyzedSources.append(analyzed)
        }
        reportProgress(
            progress,
            phase: .validatingConversationSources,
            completedUnitCount: sources.count,
            totalUnitCount: sources.count,
            unit: .sources
        )

        let individualConversationKey = try validateConversationIdentity(analyzedSources)
        let inputMessageCount = sources.reduce(0) { $0 + $1.document.messages.count }
        var analyzedMessages: [AnalyzedConversationMessage] = []
        analyzedMessages.reserveCapacity(inputMessageCount)
        var canonicalizedCount = 0

        for (sourceIndex, analyzedSource) in analyzedSources.enumerated() {
            for (messageIndex, message) in analyzedSource.source.document.messages.enumerated() {
                try checkCancellation(cancellation)
                let mediaRecord = message.mediaFilename.flatMap {
                    analyzedSource.mediaByFilename[$0]
                }
                let author = try canonicalAuthor(
                    for: message,
                    chatType: analyzedSource.source.document.chat.chatType,
                    individualConversationKey: individualConversationKey,
                    sourceID: analyzedSource.source.id
                )
                let payload = CanonicalConversationMessagePayload(
                    timestampMilliseconds: Int64(
                        (message.date.timeIntervalSince1970 * 1_000).rounded()
                    ),
                    author: author,
                    messageType: message.messageType,
                    text: normalizedMessageText(message.message),
                    caption: normalizedMessageText(message.caption),
                    media: mediaRecord?.identity,
                    seconds: message.seconds,
                    latitude: message.latitude,
                    longitude: message.longitude
                )
                let fingerprint = try stableDigest(of: payload)
                analyzedMessages.append(
                    AnalyzedConversationMessage(
                        sourceIndex: sourceIndex,
                        messageIndex: messageIndex,
                        sourceID: analyzedSource.source.id,
                        message: message,
                        materializationMessage: message,
                        fingerprint: fingerprint,
                        mediaRecord: mediaRecord
                    )
                )
                canonicalizedCount += 1
                reportProgress(
                    progress,
                    phase: .canonicalizingConversationMessages,
                    completedUnitCount: canonicalizedCount,
                    totalUnitCount: inputMessageCount,
                    unit: .messages
                )
            }
        }

        analyzedMessages.sort(by: sourceMessagePrecedes)
        var groupIndexByFingerprint: [String: Int] = [:]
        var logicalMessages: [LogicalConversationMessage] = []
        var groupIndexBySourceMessage: [ConversationSourceMessageKey: Int] = [:]
        var reasons: Set<CompositionReason> = [.samePerspectiveConstraintAccepted]

        for analyzedMessage in analyzedMessages {
            let groupIndex: Int
            if let existing = groupIndexByFingerprint[analyzedMessage.fingerprint] {
                groupIndex = existing
                if logicalMessages[existing].references.contains(where: {
                    $0.sourceID == analyzedMessage.sourceID
                }) {
                    reasons.insert(.duplicateFingerprintWithinSource)
                }
                logicalMessages[existing].references.append(analyzedMessage)
            } else {
                groupIndex = logicalMessages.count
                groupIndexByFingerprint[analyzedMessage.fingerprint] = groupIndex
                logicalMessages.append(
                    LogicalConversationMessage(
                        fingerprint: analyzedMessage.fingerprint,
                        references: [analyzedMessage],
                        stableID: ArchiveMessageID(
                            rawValue: deterministicUUID(digest: analyzedMessage.fingerprint)
                        )
                    )
                )
            }
            groupIndexBySourceMessage[analyzedMessage.key] = groupIndex
        }

        try assignStableIDs(
            to: &logicalMessages,
            analyzedSources: analyzedSources,
            targetSourceID: targetSourceID
        )
        if hasInconsistentReplies(
            logicalMessages: logicalMessages,
            groupIndexBySourceMessage: groupIndexBySourceMessage
        ) {
            reasons.insert(.inconsistentReplyMetadata)
        }

        reportProgress(
            progress,
            phase: .classifyingConversationComposition,
            completedUnitCount: logicalMessages.count,
            totalUnitCount: logicalMessages.count,
            unit: .messages
        )

        let sourceImpacts = calculateSourceImpacts(
            sources: sources,
            logicalMessages: logicalMessages
        )
        let statistics = calculateStatistics(
            analyzedSources: analyzedSources,
            logicalMessages: logicalMessages,
            inputMessageCount: inputMessageCount
        )
        let sourceDigests = analyzedSources.map {
            ConversationSourceDigest(
                sourceID: $0.source.id,
                documentDigest: $0.documentDigest,
                mediaDigest: $0.mediaDigest
            )
        }
        let plan = ConversationCompositionPlan(
            schemaVersion: 1,
            algorithmVersion: 1,
            profile: policy.profile,
            targetSourceID: targetSourceID,
            sourceDigests: sourceDigests,
            statistics: statistics,
            sourceImpacts: sourceImpacts,
            confidence: .high,
            disposition: .applicable,
            reasons: reasons.sorted { $0.rawValue < $1.rawValue },
            crossPerspectiveDiagnostic: nil
        )
        let preparation = PreparedConversationComposition(
            plan: plan,
            storage: ConversationPreparationStorage(
                analyzedSources: analyzedSources,
                logicalMessages: logicalMessages,
                groupIndexBySourceMessage: groupIndexBySourceMessage
            )
        )
        try checkCancellation(cancellation)
        if reportsCompletion {
            reportProgress(
                progress,
                phase: .completed,
                completedUnitCount: 1,
                totalUnitCount: 1,
                unit: .phases
            )
        }
        return preparation
    }

    func analyzeCrossPerspective(
        sources: [ConversationSource],
        targetSourceID: ConversationSourceID,
        perspectiveConstraints: [ConversationPerspectiveConstraint],
        progress: WABackupProgressHandler?,
        cancellation: WABackupCancellationHandler?,
        reportsCompletion: Bool
    ) throws -> PreparedConversationComposition {
        let analysis = try diagnoseCrossPerspective(
            sources: sources,
            targetSourceID: targetSourceID,
            perspectiveConstraints: perspectiveConstraints,
            progress: progress,
            cancellation: cancellation,
            reportsCompletion: false
        )
        switch analysis.diagnostic.disposition {
        case .applicable:
            break
        case .requiresReview:
            throw ConversationCompositionError.crossPerspectiveCompositionRequiresReview(
                analysis.diagnostic
            )
        case .rejected:
            throw ConversationCompositionError.crossPerspectiveCompositionRejected(
                analysis.diagnostic
            )
        }

        let pairBySourceID = Dictionary(
            uniqueKeysWithValues: analysis.pairResults.map { ($0.sourceID, $0) }
        )
        let inputMessageCount = analysis.sources.reduce(0) {
            $0 + $1.messages.count
        }
        var occurrences: [AnalyzedConversationMessage] = []
        var matchSignatureByOccurrence: [String] = []
        var occurrenceIndexByKey: [ConversationSourceMessageKey: Int] = [:]
        occurrences.reserveCapacity(inputMessageCount)
        matchSignatureByOccurrence.reserveCapacity(inputMessageCount)

        for (sourceIndex, source) in analysis.sources.enumerated() {
            let pair = pairBySourceID[source.analyzed.source.id]
            let relationship = source.analyzed.source.id == targetSourceID
                ? PerspectiveRelationship.sameAsTarget
                : pair?.relationship ?? .unresolved
            for diagnosticMessage in source.messages {
                try checkCancellation(cancellation)
                let oriented = try targetOrientedMessage(
                    diagnosticMessage,
                    source: source,
                    target: analysis.target,
                    relationship: relationship,
                    pair: pair,
                    constraints: perspectiveConstraints
                )
                let mediaRecord = diagnosticMessage.message.mediaFilename.flatMap {
                    source.analyzed.mediaByFilename[$0]
                }
                let payload = CanonicalConversationMessagePayload(
                    timestampMilliseconds: timestampMilliseconds(oriented.message.date),
                    author: oriented.canonicalAuthor,
                    messageType: diagnosticMessage.message.messageType,
                    text: normalizedMessageText(diagnosticMessage.message.message),
                    caption: normalizedMessageText(diagnosticMessage.message.caption),
                    media: mediaRecord?.identity,
                    seconds: diagnosticMessage.message.seconds,
                    latitude: diagnosticMessage.message.latitude,
                    longitude: diagnosticMessage.message.longitude
                )
                let fingerprint = try stableDigest(of: payload)
                let occurrence = AnalyzedConversationMessage(
                    sourceIndex: sourceIndex,
                    messageIndex: diagnosticMessage.index,
                    sourceID: source.analyzed.source.id,
                    message: diagnosticMessage.message,
                    materializationMessage: oriented.message,
                    fingerprint: fingerprint,
                    mediaRecord: mediaRecord
                )
                occurrenceIndexByKey[occurrence.key] = occurrences.count
                occurrences.append(occurrence)
                matchSignatureByOccurrence.append(
                    "\(oriented.canonicalAuthor)\u{0}\(diagnosticMessage.coreSignature)"
                )
            }
        }

        var unionFind = ConversationOccurrenceUnionFind(count: occurrences.count)
        for pair in analysis.pairResults {
            guard let source = analysis.sources.first(where: {
                $0.analyzed.source.id == pair.sourceID
            }) else { continue }
            for anchor in pair.anchors {
                let targetMessageID = analysis.target.messages[anchor.targetIndex].message.id
                let sourceMessageID = source.messages[anchor.sourceIndex].message.id
                guard let targetIndex = occurrenceIndexByKey[
                    ConversationSourceMessageKey(
                        sourceID: targetSourceID,
                        messageID: targetMessageID
                    )
                ], let sourceIndex = occurrenceIndexByKey[
                    ConversationSourceMessageKey(
                        sourceID: pair.sourceID,
                        messageID: sourceMessageID
                    )
                ] else { continue }
                unionFind.join(targetIndex, sourceIndex)
            }
        }

        var stableOccurrenceByID: [ArchiveMessageID: Int] = [:]
        for (index, occurrence) in occurrences.enumerated() {
            let source = analysis.sources[occurrence.sourceIndex].analyzed.source
            guard let stableID = source.stableMessageIDs[occurrence.message.id] else { continue }
            if let previous = stableOccurrenceByID[stableID] {
                guard matchSignatureByOccurrence[previous] == matchSignatureByOccurrence[index] else {
                    throw ConversationCompositionError.incompatibleStableMessageID(stableID)
                }
                unionFind.join(previous, index)
            } else {
                stableOccurrenceByID[stableID] = index
            }
        }

        let occurrencesBySignature = Dictionary(
            grouping: occurrences.indices,
            by: { matchSignatureByOccurrence[$0] }
        )
        for indices in occurrencesBySignature.values where indices.count > 1 {
            let countsBySource = Dictionary(grouping: indices, by: { occurrences[$0].sourceID })
            guard countsBySource.values.allSatisfy({ $0.count == 1 }) else { continue }
            let ordered = indices.sorted { lhs, rhs in
                let lhsIsTarget = occurrences[lhs].sourceID == targetSourceID
                let rhsIsTarget = occurrences[rhs].sourceID == targetSourceID
                if lhsIsTarget != rhsIsTarget { return lhsIsTarget }
                if occurrences[lhs].materializationMessage.date
                    != occurrences[rhs].materializationMessage.date {
                    return occurrences[lhs].materializationMessage.date
                        < occurrences[rhs].materializationMessage.date
                }
                return occurrences[lhs].sourceID.rawValue < occurrences[rhs].sourceID.rawValue
            }
            guard let reference = ordered.first else { continue }
            for index in ordered.dropFirst() {
                let difference = abs(
                    timestampMilliseconds(occurrences[index].materializationMessage.date)
                        - timestampMilliseconds(occurrences[reference].materializationMessage.date)
                )
                if difference <= policy.maximumTimestampDifferenceMilliseconds {
                    unionFind.join(reference, index)
                }
            }
        }

        var referencesByRoot: [Int: [AnalyzedConversationMessage]] = [:]
        for index in occurrences.indices {
            referencesByRoot[unionFind.root(of: index), default: []].append(occurrences[index])
        }
        var logicalMessages = try referencesByRoot.values.map { references in
            let ordered = references.sorted { lhs, rhs in
                let lhsIsTarget = lhs.sourceID == targetSourceID
                let rhsIsTarget = rhs.sourceID == targetSourceID
                if lhsIsTarget != rhsIsTarget { return lhsIsTarget }
                let lhsDate = analysis.sources[lhs.sourceIndex].analyzed.source.sourceDate
                let rhsDate = analysis.sources[rhs.sourceIndex].analyzed.source.sourceDate
                if lhsDate != rhsDate { return lhsDate > rhsDate }
                if lhs.sourceIndex != rhs.sourceIndex { return lhs.sourceIndex < rhs.sourceIndex }
                return lhs.messageIndex < rhs.messageIndex
            }
            guard let representative = ordered.first else {
                throw ConversationCompositionError.noSources
            }
            return LogicalConversationMessage(
                fingerprint: representative.fingerprint,
                references: ordered,
                stableID: ArchiveMessageID(
                    rawValue: deterministicUUID(digest: representative.fingerprint)
                )
            )
        }
        logicalMessages.sort { lhs, rhs in
            let lhsMessage = lhs.representative.materializationMessage
            let rhsMessage = rhs.representative.materializationMessage
            if lhsMessage.date != rhsMessage.date { return lhsMessage.date < rhsMessage.date }
            if lhs.representative.sourceIndex != rhs.representative.sourceIndex {
                return lhs.representative.sourceIndex < rhs.representative.sourceIndex
            }
            if lhs.representative.messageIndex != rhs.representative.messageIndex {
                return lhs.representative.messageIndex < rhs.representative.messageIndex
            }
            return lhs.fingerprint < rhs.fingerprint
        }

        var groupIndexBySourceMessage: [ConversationSourceMessageKey: Int] = [:]
        for (groupIndex, group) in logicalMessages.enumerated() {
            for reference in group.references {
                groupIndexBySourceMessage[reference.key] = groupIndex
            }
        }
        let analyzedSources = analysis.sources.map(\.analyzed)
        try assignStableIDs(
            to: &logicalMessages,
            analyzedSources: analyzedSources,
            targetSourceID: targetSourceID
        )
        var reasons = Set(analysis.diagnostic.reasons)
        if hasInconsistentReplies(
            logicalMessages: logicalMessages,
            groupIndexBySourceMessage: groupIndexBySourceMessage
        ) {
            reasons.insert(.inconsistentReplyMetadata)
        }
        reportProgress(
            progress,
            phase: .classifyingConversationComposition,
            completedUnitCount: logicalMessages.count,
            totalUnitCount: logicalMessages.count,
            unit: .messages
        )

        let orderedSources = analyzedSources.map(\.source)
        let sourceImpacts = calculateSourceImpacts(
            sources: orderedSources,
            logicalMessages: logicalMessages
        )
        let plan = ConversationCompositionPlan(
            schemaVersion: 1,
            algorithmVersion: 2,
            profile: policy.profile,
            targetSourceID: targetSourceID,
            sourceDigests: analysis.diagnostic.sourceDigests,
            statistics: calculateStatistics(
                analyzedSources: analyzedSources,
                logicalMessages: logicalMessages,
                inputMessageCount: inputMessageCount
            ),
            sourceImpacts: sourceImpacts,
            confidence: analysis.diagnostic.confidence,
            disposition: .applicable,
            reasons: reasons.sorted { $0.rawValue < $1.rawValue },
            crossPerspectiveDiagnostic: analysis.diagnostic
        )
        let preparation = PreparedConversationComposition(
            plan: plan,
            storage: ConversationPreparationStorage(
                analyzedSources: analyzedSources,
                logicalMessages: logicalMessages,
                groupIndexBySourceMessage: groupIndexBySourceMessage
            )
        )
        try checkCancellation(cancellation)
        if reportsCompletion {
            reportProgress(
                progress,
                phase: .completed,
                completedUnitCount: 1,
                totalUnitCount: 1,
                unit: .phases
            )
        }
        return preparation
    }

    func materialize(
        _ preparation: PreparedConversationComposition,
        targetChatID: Int,
        destinationDirectory: URL,
        progress: WABackupProgressHandler?,
        cancellation: WABackupCancellationHandler?,
        reportsCompletion: Bool,
        reportsValidationProgress: Bool
    ) throws -> ConversationMaterializationResult {
        guard policy.profile == preparation.plan.profile else {
            throw ConversationCompositionError.unsupportedCompositionProfile
        }
        try checkCancellation(cancellation)
        try validatePreparedInputs(
            preparation,
            progress: reportsValidationProgress ? progress : nil,
            cancellation: cancellation
        )

        let fileManager = FileManager.default
        let destination = destinationDirectory.standardizedFileURL
        var createdDestination = false
        var operationSucceeded = false
        let mediaDirectory = destination.appendingPathComponent("Media", isDirectory: true)
        let documentURL = destination.appendingPathComponent("chat.json")

        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: destination.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue,
                  (try fileManager.contentsOfDirectory(atPath: destination.path)).isEmpty else {
                throw ConversationCompositionError.destinationNotEmpty(destination)
            }
            let values = try destination.resourceValues(forKeys: [.isSymbolicLinkKey])
            guard values.isSymbolicLink != true else {
                throw ConversationCompositionError.destinationNotEmpty(destination)
            }
        } else {
            do {
                try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
                createdDestination = true
            } catch {
                throw ConversationCompositionError.fileOperation(url: destination, underlying: error)
            }
        }

        defer {
            if !operationSucceeded {
                if createdDestination {
                    try? fileManager.removeItem(at: destination)
                } else {
                    try? fileManager.removeItem(at: documentURL)
                    try? fileManager.removeItem(at: mediaDirectory)
                }
            }
        }

        do {
            try fileManager.createDirectory(at: mediaDirectory, withIntermediateDirectories: false)
        } catch {
            throw ConversationCompositionError.fileOperation(url: mediaDirectory, underlying: error)
        }

        guard let targetSource = preparation.storage.analyzedSources.first(where: {
            $0.source.id == preparation.plan.targetSourceID
        }) else {
            throw ConversationCompositionError.targetSourceNotFound(preparation.plan.targetSourceID)
        }

        reportProgress(
            progress,
            phase: .materializingConversation,
            completedUnitCount: 0,
            totalUnitCount: preparation.storage.logicalMessages.count,
            unit: .messages
        )
        let materializer = ConversationMediaMaterializer(
            destinationDirectory: mediaDirectory,
            progress: progress,
            cancellation: cancellation
        )
        var messages: [MessageInfo] = []
        var messageMediaNames = Set<String>()
        var stableMessageIDsByMaterializedID: [Int: ArchiveMessageID] = [:]

        for (groupIndex, logicalMessage) in preparation.storage.logicalMessages.enumerated() {
            try checkCancellation(cancellation)
            let representative = logicalMessage.representative
            let materializedID = groupIndex + 1
            let mediaFilename = try representative.mediaRecord.map {
                try materializer.materialize($0)
            }
            if let mediaFilename {
                messageMediaNames.insert(mediaFilename)
            }
            let replyTo = representative.message.replyTo.flatMap {
                preparation.storage.groupIndexBySourceMessage[
                    ConversationSourceMessageKey(
                        sourceID: representative.sourceID,
                        messageID: $0
                    )
                ].map { $0 + 1 }
            }
            messages.append(
                clonedMessage(
                    representative.materializationMessage,
                    id: materializedID,
                    chatID: targetChatID,
                    replyTo: replyTo,
                    mediaFilename: mediaFilename
                )
            )
            stableMessageIDsByMaterializedID[materializedID] = logicalMessage.stableID
            reportProgress(
                progress,
                phase: .materializingConversation,
                completedUnitCount: materializedID,
                totalUnitCount: preparation.storage.logicalMessages.count,
                unit: .messages
            )
        }

        let selectedContacts = chooseContacts(
            from: preparation.storage.analyzedSources,
            targetSourceID: preparation.plan.targetSourceID
        )
        let contacts = try selectedContacts.map { selected -> ContactInfo in
            let filename = try selected.contact.photoFilename.map { filename in
                guard let record = selected.source.mediaByFilename[filename] else {
                    throw ConversationCompositionError.invalidSource(
                        sourceID: selected.source.source.id,
                        reason: "A selected contact photo was not validated."
                    )
                }
                return try materializer.materialize(record)
            }
            return ContactInfo(
                name: selected.contact.name,
                phone: selected.contact.phone,
                photoFilename: filename
            )
        }

        let chatPhotoFilename = try targetSource.source.document.chat.photoFilename.map { filename in
            guard let record = targetSource.mediaByFilename[filename] else {
                throw ConversationCompositionError.invalidSource(
                    sourceID: targetSource.source.id,
                    reason: "The selected chat photo was not validated."
                )
            }
            return try materializer.materialize(record)
        }
        let messageMediaByteCount = messageMediaNames.reduce(Int64(0)) {
            $0 + materializer.byteCount(forDestinationFilename: $1)
        }
        let targetChat = targetSource.source.document.chat
        let chat = ChatInfo(
            id: targetChatID,
            contactJid: targetChat.contactJid,
            name: targetChat.name,
            numberMessages: messages.count,
            lastMessageDate: messages.last?.date ?? targetChat.lastMessageDate,
            isArchived: targetChat.isArchived,
            mediaByteCount: messageMediaByteCount,
            photoFilename: chatPhotoFilename
        )
        let exportedAt = preparation.storage.analyzedSources
            .map(\.source.sourceDate)
            .max() ?? targetSource.source.sourceDate
        let document = ExportedChatDocument(
            payload: ChatDumpPayload(chatInfo: chat, messages: messages, contacts: contacts),
            exportedAt: exportedAt
        )

        let encoder = conversationJSONEncoder()
        do {
            try encoder.encode(document).write(to: documentURL, options: .atomic)
        } catch {
            throw ConversationCompositionError.fileOperation(url: documentURL, underlying: error)
        }
        try validateMaterializedDocument(
            document,
            documentURL: documentURL,
            mediaDirectoryURL: mediaDirectory
        )

        let sourceMappings = preparation.storage.analyzedSources.map { analyzedSource in
            var mapping: [Int: ArchiveMessageID] = [:]
            for logicalMessage in preparation.storage.logicalMessages {
                for reference in logicalMessage.references where reference.sourceID == analyzedSource.source.id {
                    mapping[reference.message.id] = logicalMessage.stableID
                }
            }
            return ConversationSourceMapping(
                sourceID: analyzedSource.source.id,
                sourceMessageIDs: mapping
            )
        }
        let result = ConversationMaterializationResult(
            document: document,
            directoryURL: destination,
            documentURL: documentURL,
            mediaDirectoryURL: mediaDirectory,
            stableMessageIDsByMaterializedID: stableMessageIDsByMaterializedID,
            sourceMappings: sourceMappings,
            sourceImpacts: preparation.plan.sourceImpacts,
            statistics: ConversationMaterializationStatistics(
                messageCount: messages.count,
                copiedMediaFileCount: materializer.copiedFileCount,
                copiedMediaByteCount: materializer.copiedByteCount
            )
        )
        try checkCancellation(cancellation)
        operationSucceeded = true
        if reportsCompletion {
            reportProgress(
                progress,
                phase: .completed,
                completedUnitCount: 1,
                totalUnitCount: 1,
                unit: .phases
            )
        }
        return result
    }
}

private extension ConversationCompositionEngine {
    func diagnoseCrossPerspective(
        sources: [ConversationSource],
        targetSourceID: ConversationSourceID,
        perspectiveConstraints: [ConversationPerspectiveConstraint],
        progress: WABackupProgressHandler?,
        cancellation: WABackupCancellationHandler?,
        reportsCompletion: Bool
    ) throws -> CrossPerspectiveDiagnosticAnalysis {
        guard policy.profile == .conservativeCrossPerspective else {
            throw ConversationCompositionError.unsupportedCompositionProfile
        }
        guard !sources.isEmpty else {
            throw ConversationCompositionError.noSources
        }

        try checkCancellation(cancellation)
        var seenSourceIDs = Set<ConversationSourceID>()
        for source in sources where !seenSourceIDs.insert(source.id).inserted {
            throw ConversationCompositionError.duplicateSourceID(source.id)
        }
        guard sources.contains(where: { $0.id == targetSourceID }) else {
            throw ConversationCompositionError.targetSourceNotFound(targetSourceID)
        }
        try validateDiagnosticConstraints(
            perspectiveConstraints,
            sourceIDs: seenSourceIDs
        )

        let orderedSources = sources.sorted {
            if $0.id == targetSourceID { return true }
            if $1.id == targetSourceID { return false }
            return $0.id.rawValue < $1.id.rawValue
        }
        let referencedMediaCount = orderedSources.reduce(0) {
            $0 + Set(referencedFilenames(in: $1.document)).count
        }
        let inputMessageCount = orderedSources.reduce(0) {
            $0 + $1.document.messages.count
        }
        var hashedMediaCount = 0
        var canonicalizedMessageCount = 0
        var diagnosticSources: [DiagnosticSource] = []

        for (sourceIndex, source) in orderedSources.enumerated() {
            try checkCancellation(cancellation)
            reportProgress(
                progress,
                phase: .validatingConversationSources,
                completedUnitCount: sourceIndex,
                totalUnitCount: orderedSources.count,
                unit: .sources
            )
            let analyzed = try analyzeSource(
                source,
                cancellation: cancellation,
                didHashMedia: {
                    hashedMediaCount += 1
                    reportProgress(
                        progress,
                        phase: .hashingConversationMedia,
                        completedUnitCount: hashedMediaCount,
                        totalUnitCount: referencedMediaCount,
                        unit: .mediaFiles
                    )
                }
            )
            let messages = try analyzed.source.document.messages.enumerated().map {
                messageIndex, message in
                try checkCancellation(cancellation)
                let diagnosticMessage = try makeDiagnosticMessage(
                    message,
                    index: messageIndex,
                    source: analyzed
                )
                canonicalizedMessageCount += 1
                reportProgress(
                    progress,
                    phase: .canonicalizingConversationMessages,
                    completedUnitCount: canonicalizedMessageCount,
                    totalUnitCount: inputMessageCount,
                    unit: .messages
                )
                return diagnosticMessage
            }
            diagnosticSources.append(
                DiagnosticSource(analyzed: analyzed, messages: messages)
            )
        }
        reportProgress(
            progress,
            phase: .validatingConversationSources,
            completedUnitCount: orderedSources.count,
            totalUnitCount: orderedSources.count,
            unit: .sources
        )

        guard let target = diagnosticSources.first(where: {
            $0.analyzed.source.id == targetSourceID
        }) else {
            throw ConversationCompositionError.targetSourceNotFound(targetSourceID)
        }

        var pairResults: [DiagnosticPairResult] = []
        let comparedSources = diagnosticSources.filter {
            $0.analyzed.source.id != targetSourceID
        }
        for (index, source) in comparedSources.enumerated() {
            try checkCancellation(cancellation)
            let constraint = diagnosticConstraintResolution(
                target: target.analyzed.source,
                source: source.analyzed.source,
                constraints: perspectiveConstraints
            )
            let pair = try alignDiagnosticPair(
                target: target,
                source: source,
                constraint: constraint,
                cancellation: cancellation
            )
            pairResults.append(pair)
            reportProgress(
                progress,
                phase: .aligningConversationMessages,
                completedUnitCount: index + 1,
                totalUnitCount: comparedSources.count,
                unit: .sources
            )
            reportProgress(
                progress,
                phase: .inferringConversationPerspectives,
                completedUnitCount: index + 1,
                totalUnitCount: comparedSources.count,
                unit: .sources
            )
        }

        let targetConstraint = diagnosticIdentity(
            for: target.analyzed.source,
            constraints: perspectiveConstraints
        )
        var perspectives = [
            SourcePerspectiveResolution(
                sourceID: targetSourceID,
                inferredParticipant: targetConstraint,
                relationToTarget: .sameAsTarget,
                evidenceCount: target.messages.count,
                confidence: .high,
                reasons: []
            )
        ]
        for pair in pairResults {
            let source = diagnosticSources.first {
                $0.analyzed.source.id == pair.sourceID
            }!.analyzed.source
            let inferredParticipant = diagnosticIdentity(
                for: source,
                constraints: perspectiveConstraints
            )
            let confidence: ConversationCompositionConfidence
            if pair.relationship == .conflicting || pair.relationship == .unresolved {
                confidence = .low
            } else if pair.relationshipEvidenceCount >= policy.minimumStrongAnchorCount {
                confidence = .high
            } else {
                confidence = .medium
            }
            perspectives.append(
                SourcePerspectiveResolution(
                    sourceID: pair.sourceID,
                    inferredParticipant: inferredParticipant,
                    relationToTarget: pair.relationship,
                    evidenceCount: pair.relationshipEvidenceCount,
                    confidence: confidence,
                    reasons: pair.relationshipReasons.sorted { $0.rawValue < $1.rawValue }
                )
            )
        }

        var reasons = Set(pairResults.flatMap(\.relationshipReasons))
        let chatTypes = Set(diagnosticSources.map {
            $0.analyzed.source.document.chat.chatType
        })
        let chatType = target.analyzed.source.document.chat.chatType
        let hasSufficientOverlap = pairResults.allSatisfy {
            $0.anchors.count >= policy.minimumOverlapMessageCount
                && $0.statistics.strongAnchorCount >= policy.minimumStrongAnchorCount
        } && policy.minimumMatchedWindowCount == 0
        let hasConsistentOrder = pairResults.allSatisfy {
            $0.statistics.orderConsistency >= policy.minimumOrderConsistency
        }
        let normalizedGroupJID: String?
        var identityStatus: ConversationEquivalenceStatus

        if chatTypes.count != 1 {
            normalizedGroupJID = nil
            identityStatus = .different
        } else if chatType == .group {
            let groupJIDs = diagnosticSources.map {
                normalizedJID($0.analyzed.source.document.chat.contactJid)
            }
            if let first = groupJIDs.first,
               first.hasSuffix("@g.us"),
               groupJIDs.allSatisfy({ $0 == first }) {
                normalizedGroupJID = first
                reasons.insert(.groupJIDMatched)
                identityStatus = hasSufficientOverlap ? .same : .ambiguous
            } else {
                normalizedGroupJID = nil
                reasons.insert(.groupJIDMismatch)
                identityStatus = .different
            }
        } else {
            normalizedGroupJID = nil
            let relationshipsResolved = pairResults.allSatisfy {
                $0.relationship == .sameAsTarget || $0.relationship == .differentFromTarget
            }
            if hasSufficientOverlap && hasConsistentOrder && relationshipsResolved {
                identityStatus = .same
                reasons.insert(.individualConversationInferredFromOverlap)
            } else {
                identityStatus = .ambiguous
            }
        }

        if hasSufficientOverlap {
            reasons.insert(.strongContentOverlap)
        } else {
            reasons.insert(.insufficientContentOverlap)
        }
        if hasConsistentOrder {
            reasons.insert(.orderedAnchorsAccepted)
        } else {
            reasons.insert(.inconsistentAnchorOrder)
        }

        let pairBySourceID = Dictionary(
            uniqueKeysWithValues: pairResults.map { ($0.sourceID, $0) }
        )
        var matchedTargetIndices = Set<Int>()
        var matchedOccurrenceCount = 0
        var unorientableExclusiveCount = 0
        for pair in pairResults {
            matchedTargetIndices.formUnion(pair.matchedTargetIndices)
            matchedOccurrenceCount += pair.matchedSourceIndices.count
        }
        matchedOccurrenceCount += matchedTargetIndices.count
        let suppliedTargetIdentityKeys = diagnosticIdentity(
            for: target.analyzed.source,
            constraints: perspectiveConstraints
        )?.comparisonKeys ?? []

        for source in diagnosticSources where source.analyzed.source.id != targetSourceID {
            guard let pair = pairBySourceID[source.analyzed.source.id] else { continue }
            let relationshipResolved = pair.relationship == .sameAsTarget
                || pair.relationship == .differentFromTarget
            let suppliedSourceIdentityKeys = diagnosticIdentity(
                for: source.analyzed.source,
                constraints: perspectiveConstraints
            )?.comparisonKeys ?? []
            let targetUserKeys = pair.targetUserIdentityKeys.union(suppliedTargetIdentityKeys)
            let sourceUserKeys = pair.sourceUserIdentityKeys.union(suppliedSourceIdentityKeys)
            for message in source.messages where !pair.matchedSourceIndices.contains(message.index) {
                let groupMessageCannotBeOriented: Bool
                if chatType != .group {
                    groupMessageCannotBeOriented = false
                } else {
                    switch message.author {
                    case .sourceUser:
                        groupMessageCannotBeOriented = pair.relationship == .differentFromTarget
                            && sourceUserKeys.isEmpty
                    case .participant:
                        groupMessageCannotBeOriented = pair.relationship == .differentFromTarget
                            && targetUserKeys.isEmpty
                    case .unresolved:
                        groupMessageCannotBeOriented = true
                    }
                }
                if (!relationshipResolved && isSourceUser(message.author))
                    || groupMessageCannotBeOriented {
                    unorientableExclusiveCount += 1
                }
            }
        }

        if unorientableExclusiveCount > 0 {
            reasons.insert(.exclusiveMessagesNotOrientable)
        }
        if chatType == .group,
           diagnosticSources.flatMap(\.messages).contains(where: { !$0.author.isResolved }) {
            reasons.insert(.unresolvedGroupAuthors)
        }

        let conflictingPerspectiveCount = pairResults.filter {
            $0.relationship == .conflicting
        }.count
        let unresolvedPerspectiveCount = pairResults.filter {
            $0.relationship == .unresolved
        }.count
        let unresolvedAuthorCount = diagnosticSources.flatMap(\.messages).filter {
            !$0.author.isResolved
        }.count
        let resolvedAuthorCount = inputMessageCount - unresolvedAuthorCount
        let unresolvedAuthorFraction = inputMessageCount == 0
            ? 0
            : Double(unresolvedAuthorCount) / Double(inputMessageCount)

        let disposition: ConversationCompositionDisposition
        if identityStatus == .different
            || !hasSufficientOverlap
            || !hasConsistentOrder
            || conflictingPerspectiveCount > 0
            || unresolvedAuthorFraction > policy.maximumUnresolvedAuthorFraction
            || (policy.requireOrientableExclusiveMessages && unorientableExclusiveCount > 0) {
            disposition = .rejected
        } else if unresolvedPerspectiveCount > 0 {
            disposition = .requiresReview
        } else {
            disposition = .applicable
        }
        if identityStatus == .same && disposition != .rejected {
            identityStatus = .same
        }
        let confidence: ConversationCompositionConfidence
        switch disposition {
        case .applicable: confidence = .high
        case .requiresReview: confidence = .medium
        case .rejected: confidence = .low
        }

        let equivalence = ConversationEquivalence(
            chatType: chatType,
            status: identityStatus,
            normalizedGroupJID: normalizedGroupJID,
            perspectiveResolutions: perspectives,
            reasons: reasons.sorted { $0.rawValue < $1.rawValue }
        )
        let diagnostic = ConversationCompositionDiagnostic(
            schemaVersion: 1,
            algorithmVersion: 1,
            profile: policy.profile,
            targetSourceID: targetSourceID,
            sourceDigests: diagnosticSources.map {
                ConversationSourceDigest(
                    sourceID: $0.analyzed.source.id,
                    documentDigest: $0.analyzed.documentDigest,
                    mediaDigest: $0.analyzed.mediaDigest
                )
            },
            equivalence: equivalence,
            perspectives: perspectives,
            pairAlignments: pairResults.map(\.statistics),
            statistics: ConversationDiagnosticStatistics(
                sourceCount: diagnosticSources.count,
                inputMessageCount: inputMessageCount,
                matchedMessageCount: matchedOccurrenceCount,
                exclusiveMessageCount: max(0, inputMessageCount - matchedOccurrenceCount),
                strongAnchorCount: pairResults.reduce(0) { $0 + $1.anchors.count },
                resolvedAuthorCount: resolvedAuthorCount,
                unresolvedAuthorCount: unresolvedAuthorCount,
                unorientableExclusiveMessageCount: unorientableExclusiveCount,
                conflictingPerspectiveCount: conflictingPerspectiveCount,
                unresolvedPerspectiveCount: unresolvedPerspectiveCount
            ),
            confidence: confidence,
            disposition: disposition,
            reasons: reasons.sorted { $0.rawValue < $1.rawValue }
        )
        reportProgress(
            progress,
            phase: .classifyingConversationComposition,
            completedUnitCount: 1,
            totalUnitCount: 1,
            unit: .phases
        )
        try checkCancellation(cancellation)
        if reportsCompletion {
            reportProgress(
                progress,
                phase: .completed,
                completedUnitCount: 1,
                totalUnitCount: 1,
                unit: .phases
            )
        }
        return CrossPerspectiveDiagnosticAnalysis(
            sources: diagnosticSources,
            target: target,
            pairResults: pairResults,
            diagnostic: diagnostic
        )
    }

    func makeDiagnosticMessage(
        _ message: MessageInfo,
        index: Int,
        source: AnalyzedConversationSource
    ) throws -> DiagnosticMessage {
        let media = message.mediaFilename.flatMap {
            source.mediaByFilename[$0]?.identity
        }
        let core = DiagnosticMessageCore(
            messageType: message.messageType,
            text: normalizedMessageText(message.message),
            caption: normalizedMessageText(message.caption),
            media: media,
            seconds: message.seconds,
            latitude: message.latitude,
            longitude: message.longitude
        )
        let author = diagnosticAuthor(
            for: message,
            source: source.source
        )
        return DiagnosticMessage(
            index: index,
            message: message,
            coreSignature: try stableDigest(of: core),
            isStrong: isStrongDiagnosticCore(core),
            author: author,
            stableID: source.source.stableMessageIDs[message.id]
        )
    }

    func diagnosticAuthor(
        for message: MessageInfo,
        source: ConversationSource
    ) -> DiagnosticRelativeAuthor {
        if message.isFromMe { return .sourceUser }
        if let author = message.author {
            var keys = Set<String>()
            if let phone = author.phone {
                keys.formUnion(participantComparisonKeys(from: phone))
            }
            if let jid = author.jid {
                keys.formUnion(participantComparisonKeys(from: jid))
            }
            if !keys.isEmpty { return .participant(keys) }
        }
        if source.document.chat.chatType == .individual {
            var keys = participantComparisonKeys(from: source.document.chat.contactJid)
            if let hint = source.conversationIdentityHint {
                keys.formUnion(hint.comparisonKeys)
            }
            if !keys.isEmpty { return .participant(keys) }
        }
        return .unresolved
    }

    func targetOrientedMessage(
        _ diagnosticMessage: DiagnosticMessage,
        source: DiagnosticSource,
        target: DiagnosticSource,
        relationship: PerspectiveRelationship,
        pair: DiagnosticPairResult?,
        constraints: [ConversationPerspectiveConstraint]
    ) throws -> TargetOrientedMessage {
        guard relationship == .sameAsTarget || relationship == .differentFromTarget else {
            throw ConversationCompositionError.invalidPerspectiveConstraint(
                reason: "A source perspective is unresolved during materialization."
            )
        }
        let resolution = try targetAuthorResolution(
            diagnosticMessage.author,
            originalAuthor: diagnosticMessage.message.author,
            source: source,
            target: target,
            relationship: relationship,
            pair: pair,
            constraints: constraints
        )
        let offset = pair?.estimatedTimestampOffsetMilliseconds ?? 0
        var message = MessageInfo(
            id: diagnosticMessage.message.id,
            chatId: diagnosticMessage.message.chatId,
            message: diagnosticMessage.message.message,
            date: diagnosticMessage.message.date.addingTimeInterval(-Double(offset) / 1_000),
            isFromMe: resolution.isFromMe,
            messageType: diagnosticMessage.message.messageType,
            author: resolution.author
        )
        message.caption = diagnosticMessage.message.caption
        message.replyTo = diagnosticMessage.message.replyTo
        message.replyToPreview = diagnosticMessage.message.replyToPreview
        message.mediaFilename = diagnosticMessage.message.mediaFilename
        message.reactions = try diagnosticMessage.message.reactions?.map { reaction in
            let relativeAuthor: DiagnosticRelativeAuthor = reaction.author.kind == .me
                ? .sourceUser
                : diagnosticParticipantAuthor(reaction.author)
            let transformed = try targetAuthorResolution(
                relativeAuthor,
                originalAuthor: reaction.author,
                source: source,
                target: target,
                relationship: relationship,
                pair: pair,
                constraints: constraints
            )
            let author = transformed.author ?? MessageAuthor(
                kind: transformed.isFromMe ? .me : .participant,
                displayName: nil,
                phone: nil,
                jid: nil,
                source: transformed.isFromMe ? .owner : .messageJid
            )
            return Reaction(emoji: reaction.emoji, author: author)
        }
        message.error = diagnosticMessage.message.error
        message.seconds = diagnosticMessage.message.seconds
        message.latitude = diagnosticMessage.message.latitude
        message.longitude = diagnosticMessage.message.longitude
        return TargetOrientedMessage(
            message: message,
            canonicalAuthor: resolution.canonicalAuthor
        )
    }

    func targetAuthorResolution(
        _ relativeAuthor: DiagnosticRelativeAuthor,
        originalAuthor: MessageAuthor?,
        source: DiagnosticSource,
        target: DiagnosticSource,
        relationship: PerspectiveRelationship,
        pair: DiagnosticPairResult?,
        constraints: [ConversationPerspectiveConstraint]
    ) throws -> TargetAuthorResolution {
        if relationship == .sameAsTarget {
            switch relativeAuthor {
            case .sourceUser:
                return TargetAuthorResolution(
                    isFromMe: true,
                    author: originalAuthor,
                    canonicalAuthor: "sourceUser"
                )
            case .participant(let keys):
                return TargetAuthorResolution(
                    isFromMe: false,
                    author: originalAuthor,
                    canonicalAuthor: canonicalParticipantAuthor(keys)
                )
            case .unresolved:
                return TargetAuthorResolution(
                    isFromMe: false,
                    author: originalAuthor,
                    canonicalAuthor: "unresolved"
                )
            }
        }

        if target.analyzed.source.document.chat.chatType == .individual {
            switch relativeAuthor {
            case .sourceUser:
                let keys = targetCounterpartKeys(target.analyzed.source)
                    .union(pair?.sourceUserIdentityKeys ?? [])
                return TargetAuthorResolution(
                    isFromMe: false,
                    author: participantAuthor(
                        matching: keys,
                        in: target,
                        fallbackName: target.analyzed.source.document.chat.name
                    ),
                    canonicalAuthor: canonicalParticipantAuthor(keys)
                )
            case .participant:
                return TargetAuthorResolution(
                    isFromMe: true,
                    author: targetUserAuthor(),
                    canonicalAuthor: "sourceUser"
                )
            case .unresolved:
                throw ConversationCompositionError.invalidSource(
                    sourceID: source.analyzed.source.id,
                    reason: "An individual-chat author cannot be oriented."
                )
            }
        }

        let suppliedTargetKeys = diagnosticIdentity(
            for: target.analyzed.source,
            constraints: constraints
        )?.comparisonKeys ?? []
        let suppliedSourceKeys = diagnosticIdentity(
            for: source.analyzed.source,
            constraints: constraints
        )?.comparisonKeys ?? []
        let targetUserKeys = (pair?.targetUserIdentityKeys ?? []).union(suppliedTargetKeys)
        let sourceUserKeys = (pair?.sourceUserIdentityKeys ?? []).union(suppliedSourceKeys)
        switch relativeAuthor {
        case .sourceUser:
            guard !sourceUserKeys.isEmpty else {
                throw ConversationCompositionError.invalidSource(
                    sourceID: source.analyzed.source.id,
                    reason: "The opposite group source user has no evidence-backed identity."
                )
            }
            return TargetAuthorResolution(
                isFromMe: false,
                author: participantAuthor(
                    matching: sourceUserKeys,
                    in: target,
                    fallbackName: nil
                ),
                canonicalAuthor: canonicalParticipantAuthor(sourceUserKeys)
            )
        case .participant(let keys):
            if !targetUserKeys.isEmpty, !keys.isDisjoint(with: targetUserKeys) {
                return TargetAuthorResolution(
                    isFromMe: true,
                    author: targetUserAuthor(),
                    canonicalAuthor: "sourceUser"
                )
            }
            return TargetAuthorResolution(
                isFromMe: false,
                author: originalAuthor,
                canonicalAuthor: canonicalParticipantAuthor(keys)
            )
        case .unresolved:
            throw ConversationCompositionError.invalidSource(
                sourceID: source.analyzed.source.id,
                reason: "A group author cannot be oriented."
            )
        }
    }

    func diagnosticParticipantAuthor(_ author: MessageAuthor) -> DiagnosticRelativeAuthor {
        var keys = Set<String>()
        if let phone = author.phone {
            keys.formUnion(participantComparisonKeys(from: phone))
        }
        if let jid = author.jid {
            keys.formUnion(participantComparisonKeys(from: jid))
        }
        return keys.isEmpty ? .unresolved : .participant(keys)
    }

    func targetCounterpartKeys(_ source: ConversationSource) -> Set<String> {
        var keys = participantComparisonKeys(from: source.document.chat.contactJid)
        if let hint = source.conversationIdentityHint {
            keys.formUnion(hint.comparisonKeys)
        }
        return keys
    }

    func canonicalParticipantAuthor(_ keys: Set<String>) -> String {
        let key = keys.filter { $0.hasPrefix("phone:") }.sorted().first
            ?? keys.filter { $0.hasPrefix("lid:") }.sorted().first
            ?? "unresolved"
        return "participant:\(key)"
    }

    func targetUserAuthor() -> MessageAuthor {
        MessageAuthor(
            kind: .me,
            displayName: nil,
            phone: nil,
            jid: nil,
            source: .owner
        )
    }

    func participantAuthor(
        matching keys: Set<String>,
        in source: DiagnosticSource,
        fallbackName: String?
    ) -> MessageAuthor? {
        for message in source.messages {
            guard let author = message.message.author,
                  author.kind == .participant else { continue }
            if case .participant(let authorKeys) = message.author,
               !authorKeys.isDisjoint(with: keys) {
                return author
            }
        }
        if let phoneKey = keys.filter({ $0.hasPrefix("phone:") }).sorted().first {
            let phone = String(phoneKey.dropFirst("phone:".count))
            return MessageAuthor(
                kind: .participant,
                displayName: fallbackName,
                phone: phone,
                jid: "\(phone)@s.whatsapp.net",
                source: .messageJid
            )
        }
        if let lidKey = keys.filter({ $0.hasPrefix("lid:") }).sorted().first {
            let jid = String(lidKey.dropFirst("lid:".count))
            return MessageAuthor(
                kind: .participant,
                displayName: fallbackName,
                phone: nil,
                jid: jid,
                source: .messageJid
            )
        }
        return nil
    }

    func isStrongDiagnosticCore(_ core: DiagnosticMessageCore) -> Bool {
        if core.media != nil || core.latitude != nil || core.longitude != nil {
            return true
        }
        let content = [core.text, core.caption].compactMap { $0 }.joined(separator: "\n")
        let normalized = content.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let weakValues: Set<String> = ["ok", "sí", "si", "no", "👍", "❤️", "😂", "🙏"]
        return normalized.count >= 4 && !weakValues.contains(normalized)
    }

    func alignDiagnosticPair(
        target: DiagnosticSource,
        source: DiagnosticSource,
        constraint: DiagnosticConstraintResolution,
        cancellation: WABackupCancellationHandler?
    ) throws -> DiagnosticPairResult {
        let targetBySignature = Dictionary(grouping: target.messages, by: \.coreSignature)
        let sourceBySignature = Dictionary(grouping: source.messages, by: \.coreSignature)
        var rawCandidates: [DiagnosticAnchor] = []
        var hasStableIDConflict = false
        var targetSignatureByStableID: [ArchiveMessageID: String] = [:]
        for message in target.messages {
            if let stableID = message.stableID {
                if let existing = targetSignatureByStableID[stableID],
                   existing != message.coreSignature {
                    hasStableIDConflict = true
                } else {
                    targetSignatureByStableID[stableID] = message.coreSignature
                }
            }
        }
        for message in source.messages {
            if let stableID = message.stableID,
               let targetSignature = targetSignatureByStableID[stableID],
               targetSignature != message.coreSignature {
                hasStableIDConflict = true
            }
        }

        for signature in targetBySignature.keys.sorted() {
            try checkCancellation(cancellation)
            guard let targetMatches = targetBySignature[signature], targetMatches.count == 1,
                  let sourceMatches = sourceBySignature[signature], sourceMatches.count == 1 else {
                continue
            }
            let targetMessage = targetMatches[0]
            let sourceMessage = sourceMatches[0]
            let stableIDMatches = targetMessage.stableID != nil
                && targetMessage.stableID == sourceMessage.stableID
            guard (targetMessage.isStrong && sourceMessage.isStrong) || stableIDMatches else {
                continue
            }
            rawCandidates.append(
                DiagnosticAnchor(
                    targetIndex: targetMessage.index,
                    sourceIndex: sourceMessage.index,
                    timestampDifferenceMilliseconds: timestampMilliseconds(sourceMessage.message.date)
                        - timestampMilliseconds(targetMessage.message.date)
                )
            )
        }

        let estimatedOffset: Int64
        if policy.allowSystematicTimestampOffset {
            estimatedOffset = median(rawCandidates.map(\.timestampDifferenceMilliseconds)) ?? 0
        } else {
            estimatedOffset = 0
        }
        let candidates = rawCandidates.filter {
            abs($0.timestampDifferenceMilliseconds - estimatedOffset)
                <= policy.maximumTimestampDifferenceMilliseconds
        }.sorted {
            if $0.targetIndex != $1.targetIndex { return $0.targetIndex < $1.targetIndex }
            return $0.sourceIndex < $1.sourceIndex
        }
        let anchors = longestIncreasingAnchors(candidates)
        let orderConsistency = candidates.isEmpty
            ? 0
            : Double(anchors.count) / Double(candidates.count)

        var samePerspectiveEvidence = 0
        var differentPerspectiveEvidence = 0
        var targetIdentityEvidence: Set<String>?
        var sourceIdentityEvidence: Set<String>?
        var hasParticipantIdentityConflict = false
        for anchor in anchors {
            let targetAuthor = target.messages[anchor.targetIndex].author
            let sourceAuthor = source.messages[anchor.sourceIndex].author
            switch (targetAuthor, sourceAuthor) {
            case (.sourceUser, .sourceUser):
                samePerspectiveEvidence += 1
            case (.sourceUser, .participant(let keys)):
                differentPerspectiveEvidence += 1
                if let existing = targetIdentityEvidence,
                   existing.isDisjoint(with: keys) {
                    hasParticipantIdentityConflict = true
                }
                targetIdentityEvidence = (targetIdentityEvidence ?? keys).intersection(keys)
            case (.participant(let keys), .sourceUser):
                differentPerspectiveEvidence += 1
                if let existing = sourceIdentityEvidence,
                   existing.isDisjoint(with: keys) {
                    hasParticipantIdentityConflict = true
                }
                sourceIdentityEvidence = (sourceIdentityEvidence ?? keys).intersection(keys)
            default:
                break
            }
        }

        var reasons = constraint.reasons
        let inferredRelationship: PerspectiveRelationship
        if hasStableIDConflict {
            inferredRelationship = .conflicting
            reasons.insert(.incompatibleStableMessageID)
        } else if hasParticipantIdentityConflict
                    || (samePerspectiveEvidence > 0 && differentPerspectiveEvidence > 0) {
            inferredRelationship = .conflicting
            reasons.insert(.perspectiveEvidenceConflict)
        } else if samePerspectiveEvidence > 0 {
            inferredRelationship = .sameAsTarget
            reasons.insert(.samePerspectiveInferred)
        } else if differentPerspectiveEvidence > 0 {
            inferredRelationship = .differentFromTarget
            reasons.insert(.differentPerspectiveInferred)
        } else {
            inferredRelationship = .unresolved
            reasons.insert(.perspectiveUnresolved)
        }

        let relationship: PerspectiveRelationship
        if let constrained = constraint.relationship {
            if constrained == .conflicting {
                relationship = .conflicting
                reasons.insert(.perspectiveEvidenceConflict)
            } else if inferredRelationship != .unresolved && inferredRelationship != constrained {
                relationship = .conflicting
                reasons.insert(.perspectiveEvidenceConflict)
            } else {
                relationship = constrained
                reasons.remove(.perspectiveUnresolved)
            }
        } else {
            relationship = inferredRelationship
        }
        if estimatedOffset != 0 && policy.allowSystematicTimestampOffset {
            reasons.insert(.systematicTimestampOffsetApplied)
        }

        let differences = anchors.map { abs($0.timestampDifferenceMilliseconds) }.sorted()
        let statistics = ConversationPairAlignmentStatistics(
            sourceID: source.analyzed.source.id,
            candidateCount: candidates.count,
            strongAnchorCount: anchors.count,
            matchedMessageCount: anchors.count,
            targetMessageCount: target.messages.count,
            sourceMessageCount: source.messages.count,
            targetCoverage: coverage(anchors.count, total: target.messages.count),
            sourceCoverage: coverage(anchors.count, total: source.messages.count),
            orderConsistency: orderConsistency,
            minimumTimestampDifferenceMilliseconds: differences.first,
            maximumTimestampDifferenceMilliseconds: differences.last,
            medianTimestampDifferenceMilliseconds: median(differences),
            percentile95TimestampDifferenceMilliseconds: percentile95(differences)
        )
        return DiagnosticPairResult(
            sourceID: source.analyzed.source.id,
            anchors: anchors,
            candidateCount: candidates.count,
            relationship: relationship,
            relationshipEvidenceCount: samePerspectiveEvidence + differentPerspectiveEvidence,
            relationshipReasons: reasons,
            statistics: statistics,
            matchedTargetIndices: Set(anchors.map(\.targetIndex)),
            matchedSourceIndices: Set(anchors.map(\.sourceIndex)),
            targetUserIdentityKeys: targetIdentityEvidence ?? [],
            sourceUserIdentityKeys: sourceIdentityEvidence ?? [],
            estimatedTimestampOffsetMilliseconds: estimatedOffset
        )
    }

    func validateDiagnosticConstraints(
        _ constraints: [ConversationPerspectiveConstraint],
        sourceIDs: Set<ConversationSourceID>
    ) throws {
        for constraint in constraints {
            guard !constraint.sourceIDs.isEmpty,
                  constraint.sourceIDs.allSatisfy(sourceIDs.contains) else {
                throw ConversationCompositionError.invalidPerspectiveConstraint(
                    reason: "A constraint references an unknown or empty source set."
                )
            }
            switch constraint.kind {
            case .samePerspective:
                guard Set(constraint.sourceIDs).count == constraint.sourceIDs.count,
                      constraint.sourceIDs.count >= 2 else {
                    throw ConversationCompositionError.invalidPerspectiveConstraint(
                        reason: "A same-perspective constraint requires distinct sources."
                    )
                }
            case .differentPerspectives:
                guard Set(constraint.sourceIDs).count == 2,
                      constraint.sourceIDs.count == 2 else {
                    throw ConversationCompositionError.invalidPerspectiveConstraint(
                        reason: "A different-perspectives constraint requires two distinct sources."
                    )
                }
            case .sourceIdentity:
                guard constraint.sourceIDs.count == 1,
                      constraint.participant?.addresses.isEmpty == false else {
                    throw ConversationCompositionError.invalidPerspectiveConstraint(
                        reason: "A source-identity constraint requires one source and one identity."
                    )
                }
            }
        }
    }

    func diagnosticConstraintResolution(
        target: ConversationSource,
        source: ConversationSource,
        constraints: [ConversationPerspectiveConstraint]
    ) -> DiagnosticConstraintResolution {
        var relationships = Set<PerspectiveRelationship>()
        var reasons = Set<CompositionReason>()
        for constraint in constraints {
            let ids = Set(constraint.sourceIDs)
            switch constraint.kind {
            case .samePerspective where ids.contains(target.id) && ids.contains(source.id):
                relationships.insert(.sameAsTarget)
                reasons.insert(.perspectiveConstraintAccepted)
            case .differentPerspectives where ids == Set([target.id, source.id]):
                relationships.insert(.differentFromTarget)
                reasons.insert(.perspectiveConstraintAccepted)
            default:
                break
            }
        }

        let targetIdentity = diagnosticIdentity(for: target, constraints: constraints)
        let sourceIdentity = diagnosticIdentity(for: source, constraints: constraints)
        if let targetIdentity, let sourceIdentity {
            if !targetIdentity.comparisonKeys.isDisjoint(with: sourceIdentity.comparisonKeys) {
                relationships.insert(.sameAsTarget)
                reasons.insert(.perspectiveHintAccepted)
            } else if isAssertedIdentity(for: target, constraints: constraints)
                        && isAssertedIdentity(for: source, constraints: constraints) {
                relationships.insert(.differentFromTarget)
                reasons.insert(.perspectiveHintAccepted)
            }
        }

        let relationship: PerspectiveRelationship?
        if relationships.count > 1 {
            relationship = .conflicting
        } else {
            relationship = relationships.first
        }
        return DiagnosticConstraintResolution(
            relationship: relationship,
            reasons: reasons
        )
    }

    func diagnosticIdentity(
        for source: ConversationSource,
        constraints: [ConversationPerspectiveConstraint]
    ) -> CanonicalParticipantIdentity? {
        let constrained = constraints.first {
            $0.kind == .sourceIdentity && $0.sourceIDs == [source.id]
        }?.participant
        return constrained ?? source.perspectiveHint?.participant
    }

    func isAssertedIdentity(
        for source: ConversationSource,
        constraints: [ConversationPerspectiveConstraint]
    ) -> Bool {
        if constraints.contains(where: {
            $0.kind == .sourceIdentity && $0.sourceIDs == [source.id]
        }) {
            return true
        }
        return source.perspectiveHint?.confidence == .asserted
    }

    func longestIncreasingAnchors(_ candidates: [DiagnosticAnchor]) -> [DiagnosticAnchor] {
        guard !candidates.isEmpty else { return [] }
        var tails: [Int] = []
        var previous = Array(repeating: -1, count: candidates.count)

        for index in candidates.indices {
            var low = 0
            var high = tails.count
            while low < high {
                let middle = (low + high) / 2
                if candidates[tails[middle]].sourceIndex < candidates[index].sourceIndex {
                    low = middle + 1
                } else {
                    high = middle
                }
            }
            if low > 0 { previous[index] = tails[low - 1] }
            if low == tails.count {
                tails.append(index)
            } else {
                tails[low] = index
            }
        }

        var result: [DiagnosticAnchor] = []
        var current = tails.last ?? -1
        while current >= 0 {
            result.append(candidates[current])
            current = previous[current]
        }
        return result.reversed()
    }

    func timestampMilliseconds(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1_000).rounded())
    }

    func coverage(_ matched: Int, total: Int) -> Double {
        guard total > 0 else { return 1 }
        return Double(matched) / Double(total)
    }

    func median(_ values: [Int64]) -> Int64? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        if sorted.count.isMultiple(of: 2) {
            return (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
        }
        return sorted[sorted.count / 2]
    }

    func percentile95(_ values: [Int64]) -> Int64? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let index = Int(ceil(Double(sorted.count) * 0.95)) - 1
        return sorted[min(max(index, 0), sorted.count - 1)]
    }

    func isSourceUser(_ author: DiagnosticRelativeAuthor) -> Bool {
        if case .sourceUser = author { return true }
        return false
    }

    func validateSamePerspectiveConstraint(
        _ constraints: [ConversationPerspectiveConstraint],
        expectedSourceIDs: Set<ConversationSourceID>
    ) throws {
        guard constraints.count == 1, let constraint = constraints.first else {
            throw ConversationCompositionError.missingSamePerspectiveConstraint(
                expectedSourceIDs.sorted { $0.rawValue < $1.rawValue }
            )
        }
        guard constraint.kind == .samePerspective else {
            throw ConversationCompositionError.unsupportedCompositionProfile
        }
        let supplied = Set(constraint.sourceIDs)
        guard supplied.count == constraint.sourceIDs.count else {
            throw ConversationCompositionError.invalidPerspectiveConstraint(
                reason: "The same source appears more than once."
            )
        }
        guard supplied == expectedSourceIDs else {
            throw ConversationCompositionError.missingSamePerspectiveConstraint(
                expectedSourceIDs.sorted { $0.rawValue < $1.rawValue }
            )
        }
    }

    func analyzeSource(
        _ source: ConversationSource,
        cancellation: WABackupCancellationHandler?,
        didHashMedia: () -> Void
    ) throws -> AnalyzedConversationSource {
        let document = source.document
        guard document.chat.numberMessages == document.messages.count else {
            throw ConversationCompositionError.invalidSource(
                sourceID: source.id,
                reason: "The chat message count does not match the document."
            )
        }
        var seenMessageIDs = Set<Int>()
        for message in document.messages {
            guard message.chatId == document.chat.id else {
                throw ConversationCompositionError.invalidSource(
                    sourceID: source.id,
                    reason: "A message belongs to a different chat identifier."
                )
            }
            guard seenMessageIDs.insert(message.id).inserted else {
                throw ConversationCompositionError.invalidSource(
                    sourceID: source.id,
                    reason: "A message identifier is duplicated."
                )
            }
            if message.isFromMe, message.author?.kind == .participant {
                throw ConversationCompositionError.invalidSource(
                    sourceID: source.id,
                    reason: "An outgoing message is attributed to a participant."
                )
            }
            if !message.isFromMe, message.author?.kind == .me {
                throw ConversationCompositionError.invalidSource(
                    sourceID: source.id,
                    reason: "An incoming message is attributed to the source user."
                )
            }
            if let seconds = message.seconds, seconds < 0 {
                throw ConversationCompositionError.invalidSource(
                    sourceID: source.id,
                    reason: "A media duration is negative."
                )
            }
            if let latitude = message.latitude,
               (!latitude.isFinite || !(-90...90).contains(latitude)) {
                throw ConversationCompositionError.invalidSource(
                    sourceID: source.id,
                    reason: "A latitude is outside its valid range."
                )
            }
            if let longitude = message.longitude,
               (!longitude.isFinite || !(-180...180).contains(longitude)) {
                throw ConversationCompositionError.invalidSource(
                    sourceID: source.id,
                    reason: "A longitude is outside its valid range."
                )
            }
        }
        let messageIDSet = seenMessageIDs
        guard source.stableMessageIDs.keys.allSatisfy(messageIDSet.contains) else {
            throw ConversationCompositionError.invalidSource(
                sourceID: source.id,
                reason: "A stable message identifier refers to a missing message."
            )
        }

        let directoryValues: URLResourceValues
        do {
            directoryValues = try source.mediaDirectoryURL.resourceValues(
                forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
            )
        } catch {
            throw ConversationCompositionError.fileOperation(
                url: source.mediaDirectoryURL,
                underlying: error
            )
        }
        guard directoryValues.isDirectory == true, directoryValues.isSymbolicLink != true else {
            throw ConversationCompositionError.invalidSource(
                sourceID: source.id,
                reason: "The media path is not a regular directory."
            )
        }

        let filenames = Set(referencedFilenames(in: document))
        var mediaByFilename: [String: ConversationMediaRecord] = [:]
        for filename in filenames.sorted() {
            try checkCancellation(cancellation)
            guard isSafeMediaFilename(filename) else {
                throw ConversationCompositionError.invalidSource(
                    sourceID: source.id,
                    reason: "A referenced media filename is unsafe."
                )
            }
            let fileURL = source.mediaDirectoryURL.appendingPathComponent(filename).standardizedFileURL
            let values: URLResourceValues
            do {
                values = try fileURL.resourceValues(
                    forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey]
                )
            } catch {
                throw ConversationCompositionError.fileOperation(url: fileURL, underlying: error)
            }
            guard values.isRegularFile == true, values.isSymbolicLink != true,
                  let fileSize = values.fileSize, fileSize >= 0 else {
                throw ConversationCompositionError.invalidSource(
                    sourceID: source.id,
                    reason: "A referenced media item is missing or is not a regular file."
                )
            }
            let hash = try sha256File(fileURL, cancellation: cancellation)
            let record = ConversationMediaRecord(
                key: ConversationSourceMediaKey(sourceID: source.id, filename: filename),
                url: fileURL,
                identity: CanonicalConversationMedia(
                    sha256: hash,
                    byteCount: Int64(fileSize)
                ),
                modificationDate: values.contentModificationDate ?? .distantPast
            )
            mediaByFilename[filename] = record
            didHashMedia()
        }

        let documentDigest = try stableDigest(of: document, dateEncodingStrategy: .iso8601)
        let mediaDigestPayload = mediaByFilename.values.sorted {
            $0.key.filename < $1.key.filename
        }.map {
            "\($0.key.filename)\u{0}\($0.identity.byteCount)\u{0}\($0.identity.sha256)"
        }.joined(separator: "\n")
        return AnalyzedConversationSource(
            source: source,
            documentDigest: documentDigest,
            mediaDigest: sha256Hex(Data(mediaDigestPayload.utf8)),
            mediaByFilename: mediaByFilename
        )
    }

    func validateConversationIdentity(
        _ analyzedSources: [AnalyzedConversationSource]
    ) throws -> String? {
        guard let first = analyzedSources.first else { return nil }
        let chatType = first.source.document.chat.chatType
        guard analyzedSources.allSatisfy({ $0.source.document.chat.chatType == chatType }) else {
            throw ConversationCompositionError.differentConversations(
                reason: "The source chat types differ."
            )
        }

        switch chatType {
        case .group:
            let groupJIDs = analyzedSources.map {
                normalizedJID($0.source.document.chat.contactJid)
            }
            guard let groupJID = groupJIDs.first,
                  groupJID.hasSuffix("@g.us"),
                  groupJIDs.allSatisfy({ $0 == groupJID }) else {
                throw ConversationCompositionError.differentConversations(
                    reason: "The group JIDs differ."
                )
            }
            return nil
        case .individual:
            let sourceKeys = analyzedSources.map { analyzed -> Set<String> in
                var keys = participantComparisonKeys(from: analyzed.source.document.chat.contactJid)
                if let hint = analyzed.source.conversationIdentityHint {
                    keys.formUnion(hint.comparisonKeys)
                }
                return keys
            }
            guard sourceKeys.allSatisfy({ !$0.isEmpty }) else {
                throw ConversationCompositionError.ambiguousConversationIdentity(
                    reason: "An individual-chat counterpart has no canonical address."
                )
            }
            let common = sourceKeys.dropFirst().reduce(sourceKeys[0]) { $0.intersection($1) }
            guard !common.isEmpty else {
                throw ConversationCompositionError.differentConversations(
                    reason: "The individual-chat counterpart addresses do not match."
                )
            }
            return common.filter { $0.hasPrefix("phone:") }.sorted().first
                ?? common.sorted().first
        }
    }

    func canonicalAuthor(
        for message: MessageInfo,
        chatType: ChatInfo.ChatType,
        individualConversationKey: String?,
        sourceID: ConversationSourceID
    ) throws -> String {
        if message.isFromMe {
            if message.author?.kind == .participant {
                throw ConversationCompositionError.invalidSource(
                    sourceID: sourceID,
                    reason: "An outgoing message has a participant author."
                )
            }
            return "sourceUser"
        }
        if message.author?.kind == .me {
            throw ConversationCompositionError.invalidSource(
                sourceID: sourceID,
                reason: "An incoming message has the source-user author."
            )
        }
        if let author = message.author {
            var keys = Set<String>()
            if let phone = author.phone {
                keys.formUnion(participantComparisonKeys(from: phone))
            }
            if let jid = author.jid {
                keys.formUnion(participantComparisonKeys(from: jid))
            }
            if let phone = keys.filter({ $0.hasPrefix("phone:") }).sorted().first {
                return "participant:\(phone)"
            }
            if let first = keys.sorted().first {
                return "participant:\(first)"
            }
            return "unresolved"
        }
        if chatType == .individual, let individualConversationKey {
            return "participant:\(individualConversationKey)"
        }
        return "unresolved"
    }

    func assignStableIDs(
        to logicalMessages: inout [LogicalConversationMessage],
        analyzedSources: [AnalyzedConversationSource],
        targetSourceID: ConversationSourceID
    ) throws {
        let stableBySource = Dictionary(
            uniqueKeysWithValues: analyzedSources.map {
                ($0.source.id, $0.source.stableMessageIDs)
            }
        )
        var fingerprintByStableID: [ArchiveMessageID: String] = [:]
        for group in logicalMessages {
            for reference in group.references {
                guard let stableID = stableBySource[reference.sourceID]?[reference.message.id] else {
                    continue
                }
                if let existing = fingerprintByStableID[stableID], existing != group.fingerprint {
                    throw ConversationCompositionError.incompatibleStableMessageID(stableID)
                }
                fingerprintByStableID[stableID] = group.fingerprint
            }
        }

        for index in logicalMessages.indices {
            let references = logicalMessages[index].references
            let targetStableID = references.first(where: { $0.sourceID == targetSourceID }).flatMap {
                stableBySource[$0.sourceID]?[$0.message.id]
            }
            let firstStableID = references.lazy.compactMap {
                stableBySource[$0.sourceID]?[$0.message.id]
            }.first
            if let selected = targetStableID ?? firstStableID {
                logicalMessages[index].stableID = selected
            }
        }

        var fingerprintBySelectedID: [ArchiveMessageID: String] = [:]
        for group in logicalMessages {
            if let existing = fingerprintBySelectedID[group.stableID],
               existing != group.fingerprint {
                throw ConversationCompositionError.incompatibleStableMessageID(group.stableID)
            }
            fingerprintBySelectedID[group.stableID] = group.fingerprint
        }
    }

    func hasInconsistentReplies(
        logicalMessages: [LogicalConversationMessage],
        groupIndexBySourceMessage: [ConversationSourceMessageKey: Int]
    ) -> Bool {
        logicalMessages.contains { group in
            let targets = Set(group.references.compactMap { reference -> Int? in
                guard let replyTo = reference.message.replyTo else { return nil }
                return groupIndexBySourceMessage[
                    ConversationSourceMessageKey(
                        sourceID: reference.sourceID,
                        messageID: replyTo
                    )
                ]
            })
            return targets.count > 1
        }
    }

    func calculateSourceImpacts(
        sources: [ConversationSource],
        logicalMessages: [LogicalConversationMessage]
    ) -> [ConversationSourceImpact] {
        var mediaOwners: [CanonicalConversationMedia: Set<ConversationSourceID>] = [:]
        for group in logicalMessages {
            guard let media = group.representative.mediaRecord?.identity else { continue }
            mediaOwners[media, default: []].formUnion(group.references.map(\.sourceID))
        }

        return sources.map { source in
            let representedGroups = logicalMessages.filter { group in
                group.references.contains(where: { $0.sourceID == source.id })
            }
            let exclusive = representedGroups.filter {
                Set($0.references.map(\.sourceID)) == Set([source.id])
            }.count
            let shared = representedGroups.filter {
                Set($0.references.map(\.sourceID)).count > 1
            }.count
            let exclusiveMedia = mediaOwners.reduce(Int64(0)) { partial, entry in
                partial + (entry.value == Set([source.id]) ? entry.key.byteCount : 0)
            }
            return ConversationSourceImpact(
                sourceID: source.id,
                sourceMessageCount: source.document.messages.count,
                exclusiveMessageCount: exclusive,
                sharedMessageCount: shared,
                exclusiveMediaByteCount: exclusiveMedia
            )
        }
    }

    func calculateStatistics(
        analyzedSources: [AnalyzedConversationSource],
        logicalMessages: [LogicalConversationMessage],
        inputMessageCount: Int
    ) -> ConversationCompositionStatistics {
        let inputMessageMediaBytes = analyzedSources.reduce(Int64(0)) { sourceTotal, analyzed in
            let messageFilenames = Set(analyzed.source.document.messages.compactMap(\.mediaFilename))
            return sourceTotal + messageFilenames.reduce(Int64(0)) {
                $0 + (analyzed.mediaByFilename[$1]?.identity.byteCount ?? 0)
            }
        }
        let materializedMedia = Set(logicalMessages.compactMap {
            $0.representative.mediaRecord?.identity
        })
        let materializedMediaBytes = materializedMedia.reduce(Int64(0)) { $0 + $1.byteCount }
        let sharedCount = logicalMessages.filter {
            Set($0.references.map(\.sourceID)).count > 1
        }.count
        return ConversationCompositionStatistics(
            sourceCount: analyzedSources.count,
            inputMessageCount: inputMessageCount,
            materializedMessageCount: logicalMessages.count,
            deduplicatedOccurrenceCount: inputMessageCount - logicalMessages.count,
            sharedLogicalMessageCount: sharedCount,
            exclusiveLogicalMessageCount: logicalMessages.count - sharedCount,
            inputMediaByteCount: inputMessageMediaBytes,
            materializedMediaByteCount: materializedMediaBytes,
            duplicateMediaByteCount: max(0, inputMessageMediaBytes - materializedMediaBytes)
        )
    }

    func validatePreparedInputs(
        _ preparation: PreparedConversationComposition,
        progress: WABackupProgressHandler?,
        cancellation: WABackupCancellationHandler?
    ) throws {
        for (index, expected) in preparation.storage.analyzedSources.enumerated() {
            try checkCancellation(cancellation)
            reportProgress(
                progress,
                phase: .validatingConversationSources,
                completedUnitCount: index,
                totalUnitCount: preparation.storage.analyzedSources.count,
                unit: .sources
            )
            let current = try analyzeSource(
                expected.source,
                cancellation: cancellation,
                didHashMedia: {}
            )
            guard current.documentDigest == expected.documentDigest,
                  current.mediaDigest == expected.mediaDigest,
                  current.mediaByFilename == expected.mediaByFilename else {
                throw ConversationCompositionError.inputChanged(sourceID: expected.source.id)
            }
        }
        reportProgress(
            progress,
            phase: .validatingConversationSources,
            completedUnitCount: preparation.storage.analyzedSources.count,
            totalUnitCount: preparation.storage.analyzedSources.count,
            unit: .sources
        )
    }

    struct SelectedContact {
        let contact: ContactInfo
        let source: AnalyzedConversationSource
        let sourceIndex: Int
    }

    func chooseContacts(
        from sources: [AnalyzedConversationSource],
        targetSourceID: ConversationSourceID
    ) -> [SelectedContact] {
        var candidates: [String: [SelectedContact]] = [:]
        for (sourceIndex, source) in sources.enumerated() {
            for contact in source.source.document.contacts {
                let digits = contact.phone.filter(\.isNumber)
                let key = digits.isEmpty
                    ? "raw:\(contact.phone.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
                    : "phone:\(digits)"
                candidates[key, default: []].append(
                    SelectedContact(contact: contact, source: source, sourceIndex: sourceIndex)
                )
            }
        }
        return candidates.keys.sorted().compactMap { key in
            candidates[key]?.sorted { lhs, rhs in
                let lhsIsTarget = lhs.source.source.id == targetSourceID
                let rhsIsTarget = rhs.source.source.id == targetSourceID
                if lhsIsTarget != rhsIsTarget { return lhsIsTarget }
                if lhs.source.source.sourceDate != rhs.source.source.sourceDate {
                    return lhs.source.source.sourceDate > rhs.source.source.sourceDate
                }
                return lhs.sourceIndex < rhs.sourceIndex
            }.first
        }
    }

    func clonedMessage(
        _ source: MessageInfo,
        id: Int,
        chatID: Int,
        replyTo: Int?,
        mediaFilename: String?
    ) -> MessageInfo {
        var message = MessageInfo(
            id: id,
            chatId: chatID,
            message: source.message,
            date: source.date,
            isFromMe: source.isFromMe,
            messageType: source.messageType,
            author: source.author
        )
        message.caption = source.caption
        message.replyTo = replyTo
        message.replyToPreview = source.replyToPreview
        message.mediaFilename = mediaFilename
        message.reactions = source.reactions
        message.error = source.error
        message.seconds = source.seconds
        message.latitude = source.latitude
        message.longitude = source.longitude
        return message
    }

    func validateMaterializedDocument(
        _ expected: ExportedChatDocument,
        documentURL: URL,
        mediaDirectoryURL: URL
    ) throws {
        let decoded: ExportedChatDocument
        do {
            let data = try Data(contentsOf: documentURL)
            decoded = try conversationJSONDecoder().decode(ExportedChatDocument.self, from: data)
            try ChatExportStore.validate(
                document: decoded,
                documentURL: documentURL,
                mediaDirectoryURL: mediaDirectoryURL
            )
        } catch {
            throw ConversationCompositionError.invalidMaterializedOutput(
                url: documentURL,
                reason: error.localizedDescription
            )
        }
        let expectedMessageIDs = decoded.messages.isEmpty
            ? []
            : Array(1...decoded.messages.count)
        guard decoded.chat.id == expected.chat.id,
              decoded.chat.numberMessages == decoded.messages.count,
              decoded.messages.map(\.id) == expectedMessageIDs,
              decoded.messages.allSatisfy({ $0.chatId == decoded.chat.id }) else {
            throw ConversationCompositionError.invalidMaterializedOutput(
                url: documentURL,
                reason: "The decoded document violates message identifier invariants."
            )
        }
    }
}

private final class ConversationMediaMaterializer {
    private let destinationDirectory: URL
    private let progress: WABackupProgressHandler?
    private let cancellation: WABackupCancellationHandler?
    private var filenameByContent: [CanonicalConversationMedia: String] = [:]
    private var contentByFilename: [String: CanonicalConversationMedia] = [:]
    private var byteCountByFilename: [String: Int64] = [:]

    private(set) var copiedFileCount = 0
    private(set) var copiedByteCount: Int64 = 0

    init(
        destinationDirectory: URL,
        progress: WABackupProgressHandler?,
        cancellation: WABackupCancellationHandler?
    ) {
        self.destinationDirectory = destinationDirectory
        self.progress = progress
        self.cancellation = cancellation
    }

    func materialize(_ record: ConversationMediaRecord) throws -> String {
        if let existing = filenameByContent[record.identity] {
            return existing
        }
        try checkCancellation(cancellation)
        let destinationFilename = uniqueDestinationFilename(for: record)
        let destinationURL = destinationDirectory.appendingPathComponent(destinationFilename)
        let fileManager = FileManager.default
        guard fileManager.createFile(atPath: destinationURL.path, contents: nil) else {
            throw ConversationCompositionError.fileOperation(
                url: destinationURL,
                underlying: CocoaError(.fileWriteUnknown)
            )
        }

        do {
            let copied = try copyAndHashFile(
                from: record.url,
                to: destinationURL,
                cancellation: cancellation
            )
            guard copied.digest == record.identity.sha256,
                  copied.byteCount == record.identity.byteCount else {
                throw ConversationCompositionError.inputChanged(sourceID: record.key.sourceID)
            }
        } catch {
            try? fileManager.removeItem(at: destinationURL)
            if let error = error as? ConversationCompositionError { throw error }
            throw ConversationCompositionError.fileOperation(url: record.url, underlying: error)
        }

        filenameByContent[record.identity] = destinationFilename
        contentByFilename[destinationFilename] = record.identity
        byteCountByFilename[destinationFilename] = record.identity.byteCount
        copiedFileCount += 1
        copiedByteCount += record.identity.byteCount
        reportProgress(
            progress,
            phase: .copyingConversationMedia,
            completedUnitCount: copiedFileCount,
            totalUnitCount: nil,
            unit: .mediaFiles
        )
        return destinationFilename
    }

    func byteCount(forDestinationFilename filename: String) -> Int64 {
        byteCountByFilename[filename] ?? 0
    }

    private func uniqueDestinationFilename(for record: ConversationMediaRecord) -> String {
        let safeOriginalName = record.key.filename
        var prefixLength = min(12, record.identity.sha256.count)
        while true {
            let prefix = record.identity.sha256.prefix(prefixLength)
            let candidate = "\(prefix)-\(safeOriginalName)"
            if contentByFilename[candidate] == nil
                || contentByFilename[candidate] == record.identity {
                return candidate
            }
            if prefixLength < record.identity.sha256.count {
                prefixLength = min(prefixLength + 4, record.identity.sha256.count)
            } else {
                return "\(record.identity.sha256)-\(record.identity.byteCount)-\(safeOriginalName)"
            }
        }
    }
}

private func sourceMessagePrecedes(
    _ lhs: AnalyzedConversationMessage,
    _ rhs: AnalyzedConversationMessage
) -> Bool {
    if lhs.message.date != rhs.message.date { return lhs.message.date < rhs.message.date }
    if lhs.sourceIndex != rhs.sourceIndex { return lhs.sourceIndex < rhs.sourceIndex }
    return lhs.messageIndex < rhs.messageIndex
}

private func referencedFilenames(in document: ExportedChatDocument) -> [String] {
    [document.chat.photoFilename].compactMap { $0 }
        + document.messages.compactMap(\.mediaFilename)
        + document.contacts.compactMap(\.photoFilename)
}

private func isSafeMediaFilename(_ filename: String) -> Bool {
    !filename.isEmpty
        && filename != "."
        && filename != ".."
        && !filename.contains("/")
        && !filename.contains("\\")
        && !filename.contains("\0")
        && URL(fileURLWithPath: filename).lastPathComponent == filename
}

private func normalizedJID(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
        .precomposedStringWithCanonicalMapping
        .lowercased()
}

private func participantComparisonKeys(from value: String) -> Set<String> {
    let normalized = normalizedJID(value)
    guard !normalized.isEmpty else { return [] }
    if normalized.hasSuffix("@s.whatsapp.net") {
        let digits = String(normalized.prefix { $0 != "@" }).filter(\.isNumber)
        return digits.isEmpty ? [] : ["phone:\(digits)"]
    }
    if normalized.hasSuffix("@lid"), normalized.first != "@" {
        return ["lid:\(normalized)"]
    }
    if !normalized.contains("@") {
        let digits = normalized.filter(\.isNumber)
        return digits.isEmpty ? [] : ["phone:\(digits)"]
    }
    return ["jid:\(normalized)"]
}

private func normalizedMessageText(_ value: String?) -> String? {
    value?
        .replacingOccurrences(of: "\r\n", with: "\n")
        .replacingOccurrences(of: "\r", with: "\n")
        .precomposedStringWithCanonicalMapping
}

private func conversationJSONEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return encoder
}

private func conversationJSONDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
}

private func stableDigest<T: Encodable>(
    of value: T,
    dateEncodingStrategy: JSONEncoder.DateEncodingStrategy? = nil
) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    if let dateEncodingStrategy {
        encoder.dateEncodingStrategy = dateEncodingStrategy
    }
    return sha256Hex(try encoder.encode(value))
}

func sha256File(
    _ url: URL,
    cancellation: WABackupCancellationHandler?
) throws -> String {
    do {
        let handle = try FileHandle(forReadingFrom: url)
        defer { handle.closeFile() }
#if canImport(CryptoKit)
        if #available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *) {
            var hasher = SHA256()
            while true {
                let data = handle.readData(ofLength: 1_048_576)
                if data.isEmpty { break }
                try checkCancellation(cancellation)
                hasher.update(data: data)
            }
            return hasher.finalize().map { String(format: "%02x", $0) }.joined()
        }
#endif
        var hasher = ConversationSHA256()
        while true {
            let data = handle.readData(ofLength: 1_048_576)
            if data.isEmpty { break }
            try checkCancellation(cancellation)
            hasher.update(data: data)
        }
        return hasher.finalizeHex()
    } catch {
        if let error = error as? ConversationCompositionError { throw error }
        throw ConversationCompositionError.fileOperation(url: url, underlying: error)
    }
}

private func sha256Hex(_ data: Data) -> String {
#if canImport(CryptoKit)
    if #available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *) {
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
#endif
    return ConversationSHA256.hashHex(data)
}

private func copyAndHashFile(
    from sourceURL: URL,
    to destinationURL: URL,
    cancellation: WABackupCancellationHandler?
) throws -> (digest: String, byteCount: Int64) {
    let input = try FileHandle(forReadingFrom: sourceURL)
    let output = try FileHandle(forWritingTo: destinationURL)
    defer {
        input.closeFile()
        output.closeFile()
    }
    var byteCount: Int64 = 0
#if canImport(CryptoKit)
    if #available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *) {
        var hasher = SHA256()
        while true {
            let data = input.readData(ofLength: 1_048_576)
            if data.isEmpty { break }
            try checkCancellation(cancellation)
            hasher.update(data: data)
            output.write(data)
            byteCount += Int64(data.count)
        }
        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        return (digest, byteCount)
    }
#endif
    var hasher = ConversationSHA256()
    while true {
        let data = input.readData(ofLength: 1_048_576)
        if data.isEmpty { break }
        try checkCancellation(cancellation)
        hasher.update(data: data)
        output.write(data)
        byteCount += Int64(data.count)
    }
    return (hasher.finalizeHex(), byteCount)
}

private func deterministicUUID(digest: String) -> UUID {
    var bytes: [UInt8] = stride(from: 0, to: min(32, digest.count), by: 2).compactMap { index in
        let start = digest.index(digest.startIndex, offsetBy: index)
        let end = digest.index(start, offsetBy: min(2, digest.distance(from: start, to: digest.endIndex)))
        return UInt8(digest[start..<end], radix: 16)
    }
    while bytes.count < 16 { bytes.append(0) }
    bytes[6] = (bytes[6] & 0x0F) | 0x50
    bytes[8] = (bytes[8] & 0x3F) | 0x80
    return UUID(uuid: (
        bytes[0], bytes[1], bytes[2], bytes[3],
        bytes[4], bytes[5], bytes[6], bytes[7],
        bytes[8], bytes[9], bytes[10], bytes[11],
        bytes[12], bytes[13], bytes[14], bytes[15]
    ))
}

private func checkCancellation(_ cancellation: WABackupCancellationHandler?) throws {
    if cancellation?() == true {
        throw ConversationCompositionError.cancelled
    }
}

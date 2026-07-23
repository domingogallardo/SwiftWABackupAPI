import Foundation
import XCTest
@testable import SwiftWABackupAPI

final class CrossPerspectiveConversationDiagnosticsTests: XCTestCase {
    private let policy = ConversationCompositionPolicy(
        profile: .conservativeCrossPerspective,
        maximumTimestampDifferenceMilliseconds: 1_000,
        minimumStrongAnchorCount: 3,
        minimumOverlapMessageCount: 3,
        minimumOrderConsistency: 0.9
    )

    func testSamePerspectiveGroupIsApplicable() throws {
        let fixture = try ConversationFixture()
        defer { fixture.remove() }
        let target = try fixture.source(
            id: "target",
            chatID: 1,
            jid: "family@g.us",
            messages: samePerspectiveMessages(chatID: 1)
        )
        let source = try fixture.source(
            id: "source",
            chatID: 2,
            jid: "family@g.us",
            messages: samePerspectiveMessages(chatID: 2)
                + [.text(id: 4, chatID: 2, offset: 4, text: "Exclusive source message")]
        )

        let diagnostic = try engine().diagnose(
            sources: [target, source],
            targetSourceID: target.id
        )

        XCTAssertEqual(diagnostic.equivalence.status, .same)
        XCTAssertEqual(diagnostic.disposition, .applicable)
        XCTAssertEqual(diagnostic.perspectives[1].relationToTarget, .sameAsTarget)
        XCTAssertEqual(diagnostic.pairAlignments[0].strongAnchorCount, 3)
        XCTAssertTrue(diagnostic.reasons.contains(.groupJIDMatched))
    }

    func testOppositeGroupPerspectiveIsInferredAndExclusiveMessagesAreOrientable() throws {
        let fixture = try ConversationFixture()
        defer { fixture.remove() }
        let participantA = author(phone: "34600000001")
        let participantB = author(phone: "34600000002")
        let target = try fixture.source(
            id: "target",
            chatID: 1,
            jid: "family@g.us",
            messages: [
                .text(id: 1, chatID: 1, offset: 1, text: "First shared message", isFromMe: true),
                .text(id: 2, chatID: 1, offset: 2, text: "Second shared message", isFromMe: false, author: participantB),
                .text(id: 3, chatID: 1, offset: 3, text: "Third shared message", isFromMe: true)
            ]
        )
        let source = try fixture.source(
            id: "source",
            chatID: 2,
            jid: "family@g.us",
            messages: [
                .text(id: 11, chatID: 2, offset: 1, text: "First shared message", isFromMe: false, author: participantA),
                .text(id: 12, chatID: 2, offset: 2, text: "Second shared message", isFromMe: true),
                .text(id: 13, chatID: 2, offset: 3, text: "Third shared message", isFromMe: false, author: participantA),
                .text(id: 14, chatID: 2, offset: 4, text: "New message from source user", isFromMe: true)
            ]
        )

        let diagnostic = try engine().diagnose(
            sources: [target, source],
            targetSourceID: target.id
        )

        XCTAssertEqual(diagnostic.equivalence.status, .same)
        XCTAssertEqual(diagnostic.disposition, .applicable)
        XCTAssertEqual(diagnostic.perspectives[1].relationToTarget, .differentFromTarget)
        XCTAssertEqual(diagnostic.statistics.unorientableExclusiveMessageCount, 0)
        XCTAssertTrue(diagnostic.reasons.contains(.differentPerspectiveInferred))
    }

    func testOppositeIndividualPerspectiveCanBeInferredWithoutOwnerIdentity() throws {
        let fixture = try ConversationFixture()
        defer { fixture.remove() }
        let target = try fixture.source(
            id: "target",
            chatID: 1,
            jid: "34600000002@s.whatsapp.net",
            messages: [
                .text(id: 1, chatID: 1, offset: 1, text: "One shared individual", isFromMe: true),
                .text(id: 2, chatID: 1, offset: 2, text: "Two shared individual", isFromMe: false),
                .text(id: 3, chatID: 1, offset: 3, text: "Three shared individual", isFromMe: true)
            ]
        )
        let source = try fixture.source(
            id: "source",
            chatID: 2,
            jid: "34600000001@s.whatsapp.net",
            messages: [
                .text(id: 11, chatID: 2, offset: 1, text: "One shared individual", isFromMe: false),
                .text(id: 12, chatID: 2, offset: 2, text: "Two shared individual", isFromMe: true),
                .text(id: 13, chatID: 2, offset: 3, text: "Three shared individual", isFromMe: false)
            ]
        )

        let diagnostic = try engine().diagnose(
            sources: [target, source],
            targetSourceID: target.id
        )

        XCTAssertEqual(diagnostic.equivalence.status, .same)
        XCTAssertEqual(diagnostic.perspectives[1].relationToTarget, .differentFromTarget)
        XCTAssertNil(diagnostic.perspectives[0].inferredParticipant)
        XCTAssertNil(diagnostic.perspectives[1].inferredParticipant)
    }

    func testSameNameWithDifferentGroupJIDsIsRejectedAsDifferentConversation() throws {
        let fixture = try ConversationFixture()
        defer { fixture.remove() }
        let target = try fixture.source(
            id: "target",
            chatID: 1,
            jid: "one@g.us",
            name: "Same visible name",
            messages: samePerspectiveMessages(chatID: 1)
        )
        let source = try fixture.source(
            id: "source",
            chatID: 2,
            jid: "two@g.us",
            name: "Same visible name",
            messages: samePerspectiveMessages(chatID: 2)
        )

        let diagnostic = try engine().diagnose(
            sources: [target, source],
            targetSourceID: target.id
        )

        XCTAssertEqual(diagnostic.equivalence.status, .different)
        XCTAssertEqual(diagnostic.disposition, .rejected)
        XCTAssertTrue(diagnostic.reasons.contains(.groupJIDMismatch))
    }

    func testInsufficientOverlapIsARejectedDiagnosticNotAThrownSemanticError() throws {
        let fixture = try ConversationFixture()
        defer { fixture.remove() }
        let target = try fixture.source(
            id: "target",
            chatID: 1,
            messages: [.text(id: 1, chatID: 1, offset: 1, text: "Only shared anchor")]
        )
        let source = try fixture.source(
            id: "source",
            chatID: 2,
            messages: [.text(id: 2, chatID: 2, offset: 1, text: "Only shared anchor")]
        )

        let diagnostic = try engine().diagnose(
            sources: [target, source],
            targetSourceID: target.id
        )

        XCTAssertEqual(diagnostic.disposition, .rejected)
        XCTAssertEqual(diagnostic.equivalence.status, .ambiguous)
        XCTAssertTrue(diagnostic.reasons.contains(.insufficientContentOverlap))
    }

    func testDisjointSequencesAreNotConcatenatedEvenForTheSameGroup() throws {
        let fixture = try ConversationFixture()
        defer { fixture.remove() }
        let target = try fixture.source(
            id: "target",
            chatID: 1,
            messages: [
                .text(id: 1, chatID: 1, offset: 1, text: "Target message alpha"),
                .text(id: 2, chatID: 1, offset: 2, text: "Target message beta"),
                .text(id: 3, chatID: 1, offset: 3, text: "Target message gamma")
            ]
        )
        let source = try fixture.source(
            id: "source",
            chatID: 2,
            messages: [
                .text(id: 11, chatID: 2, offset: 4, text: "Source message delta"),
                .text(id: 12, chatID: 2, offset: 5, text: "Source message epsilon"),
                .text(id: 13, chatID: 2, offset: 6, text: "Source message zeta")
            ]
        )

        let diagnostic = try engine().diagnose(
            sources: [target, source],
            targetSourceID: target.id
        )

        XCTAssertEqual(diagnostic.pairAlignments[0].strongAnchorCount, 0)
        XCTAssertEqual(diagnostic.disposition, .rejected)
    }

    func testTimestampToleranceAndOptionalSystematicOffsetAreApplied() throws {
        let fixture = try ConversationFixture()
        defer { fixture.remove() }
        let target = try fixture.source(
            id: "target",
            chatID: 1,
            messages: samePerspectiveMessages(chatID: 1)
        )
        let shifted = try fixture.source(
            id: "shifted",
            chatID: 2,
            messages: [
                .text(id: 11, chatID: 2, offset: 11, text: "First shared message", isFromMe: true),
                .text(id: 12, chatID: 2, offset: 12, text: "Second shared message", isFromMe: false, author: author(phone: "34600000002")),
                .text(id: 13, chatID: 2, offset: 13, text: "Third shared message", isFromMe: true)
            ]
        )
        let strict = try engine().diagnose(
            sources: [target, shifted],
            targetSourceID: target.id
        )
        let offsetPolicy = ConversationCompositionPolicy(
            profile: .conservativeCrossPerspective,
            maximumTimestampDifferenceMilliseconds: 1_000,
            minimumStrongAnchorCount: 3,
            minimumOverlapMessageCount: 3,
            minimumOrderConsistency: 0.9,
            allowSystematicTimestampOffset: true
        )
        let offset = try ConversationCompositionEngine(policy: offsetPolicy).diagnose(
            sources: [target, shifted],
            targetSourceID: target.id
        )

        XCTAssertEqual(strict.disposition, .rejected)
        XCTAssertEqual(offset.disposition, .applicable)
        XCTAssertTrue(offset.reasons.contains(.systematicTimestampOffsetApplied))
    }

    func testWeakRepetitiveMessagesDoNotBecomeStrongAnchors() throws {
        let fixture = try ConversationFixture()
        defer { fixture.remove() }
        let target = try fixture.source(
            id: "target",
            chatID: 1,
            messages: [
                .text(id: 1, chatID: 1, offset: 1, text: "OK"),
                .text(id: 2, chatID: 1, offset: 2, text: "Sí"),
                .text(id: 3, chatID: 1, offset: 3, text: "👍")
            ]
        )
        let source = try fixture.source(
            id: "source",
            chatID: 2,
            messages: [
                .text(id: 11, chatID: 2, offset: 1, text: "OK"),
                .text(id: 12, chatID: 2, offset: 2, text: "Sí"),
                .text(id: 13, chatID: 2, offset: 3, text: "👍")
            ]
        )

        let diagnostic = try engine().diagnose(
            sources: [target, source],
            targetSourceID: target.id
        )

        XCTAssertEqual(diagnostic.pairAlignments[0].candidateCount, 0)
        XCTAssertEqual(diagnostic.disposition, .rejected)
    }

    func testMatchingStableIDCanAnchorWeakContentAndIncompatibleContentConflicts() throws {
        let fixture = try ConversationFixture()
        defer { fixture.remove() }
        let stableID = ArchiveMessageID(
            rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000099")!
        )
        let target = try fixture.source(
            id: "target",
            chatID: 1,
            messages: [.text(id: 1, chatID: 1, offset: 1, text: "OK")],
            stableMessageIDs: [1: stableID]
        )
        let matching = try fixture.source(
            id: "matching",
            chatID: 2,
            messages: [.text(id: 2, chatID: 2, offset: 1, text: "OK")],
            stableMessageIDs: [2: stableID]
        )
        let incompatible = try fixture.source(
            id: "incompatible",
            chatID: 3,
            messages: [.text(id: 3, chatID: 3, offset: 1, text: "Different content")],
            stableMessageIDs: [3: stableID]
        )
        let oneAnchorPolicy = ConversationCompositionPolicy(
            profile: .conservativeCrossPerspective,
            maximumTimestampDifferenceMilliseconds: 1_000,
            minimumStrongAnchorCount: 1,
            minimumOverlapMessageCount: 1,
            minimumOrderConsistency: 1
        )
        let stableEngine = ConversationCompositionEngine(policy: oneAnchorPolicy)

        let accepted = try stableEngine.diagnose(
            sources: [target, matching],
            targetSourceID: target.id
        )
        let rejected = try stableEngine.diagnose(
            sources: [target, incompatible],
            targetSourceID: target.id
        )

        XCTAssertEqual(accepted.pairAlignments[0].strongAnchorCount, 1)
        XCTAssertEqual(accepted.disposition, .applicable)
        XCTAssertEqual(rejected.perspectives[1].relationToTarget, .conflicting)
        XCTAssertTrue(rejected.reasons.contains(.incompatibleStableMessageID))
        XCTAssertEqual(rejected.disposition, .rejected)
    }

    func testSourceWithoutOwnMessagesNeedsReviewUnlessRelationshipIsSupplied() throws {
        let fixture = try ConversationFixture()
        defer { fixture.remove() }
        let participant = author(phone: "34600000003")
        let messages: [ConversationFixture.Message] = [
            .text(id: 1, chatID: 1, offset: 1, text: "First participant message", isFromMe: false, author: participant),
            .text(id: 2, chatID: 1, offset: 2, text: "Second participant message", isFromMe: false, author: participant),
            .text(id: 3, chatID: 1, offset: 3, text: "Third participant message", isFromMe: false, author: participant)
        ]
        let target = try fixture.source(id: "target", chatID: 1, messages: messages)
        let source = try fixture.source(
            id: "source",
            chatID: 2,
            messages: messages.map {
                .text(
                    id: $0.id + 10,
                    chatID: 2,
                    offset: $0.offset,
                    text: $0.text ?? "",
                    isFromMe: false,
                    author: participant
                )
            }
        )

        let unresolved = try engine().diagnose(
            sources: [target, source],
            targetSourceID: target.id
        )
        let supplied = try engine().diagnose(
            sources: [target, source],
            targetSourceID: target.id,
            perspectiveConstraints: [.samePerspective(sourceIDs: [target.id, source.id])]
        )

        XCTAssertEqual(unresolved.perspectives[1].relationToTarget, .unresolved)
        XCTAssertEqual(unresolved.disposition, .requiresReview)
        XCTAssertEqual(supplied.perspectives[1].relationToTarget, .sameAsTarget)
        XCTAssertEqual(supplied.disposition, .applicable)
    }

    func testConstraintCanResolveAContentSupportedPerspectiveButContradictionConflicts() throws {
        let fixture = try ConversationFixture()
        defer { fixture.remove() }
        let target = try fixture.source(
            id: "target",
            chatID: 1,
            messages: samePerspectiveMessages(chatID: 1)
        )
        let source = try fixture.source(
            id: "source",
            chatID: 2,
            messages: samePerspectiveMessages(chatID: 2)
        )

        let accepted = try engine().diagnose(
            sources: [target, source],
            targetSourceID: target.id,
            perspectiveConstraints: [.samePerspective(sourceIDs: [target.id, source.id])]
        )
        let contradicted = try engine().diagnose(
            sources: [target, source],
            targetSourceID: target.id,
            perspectiveConstraints: [.differentPerspectives(target.id, source.id)]
        )

        XCTAssertEqual(accepted.perspectives[1].relationToTarget, .sameAsTarget)
        XCTAssertEqual(accepted.disposition, .applicable)
        XCTAssertEqual(contradicted.perspectives[1].relationToTarget, .conflicting)
        XCTAssertEqual(contradicted.disposition, .rejected)
    }

    func testDiagnosisReportsProgressAndSupportsCancellation() throws {
        let fixture = try ConversationFixture()
        defer { fixture.remove() }
        let target = try fixture.source(
            id: "target",
            chatID: 1,
            messages: samePerspectiveMessages(chatID: 1)
        )
        let source = try fixture.source(
            id: "source",
            chatID: 2,
            messages: samePerspectiveMessages(chatID: 2)
        )
        var phases: [WABackupProgress.Phase] = []

        _ = try engine().diagnose(
            sources: [target, source],
            targetSourceID: target.id,
            progress: { phases.append($0.phase) }
        )

        XCTAssertTrue(phases.contains(.inferringConversationPerspectives))
        XCTAssertTrue(phases.contains(.aligningConversationMessages))
        XCTAssertEqual(phases.last, .completed)
        XCTAssertThrowsError(
            try engine().diagnose(
                sources: [target, source],
                targetSourceID: target.id,
                cancellation: { true }
            )
        ) { error in
            guard case ConversationCompositionError.cancelled = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    private func engine() -> ConversationCompositionEngine {
        ConversationCompositionEngine(policy: policy)
    }

    private func samePerspectiveMessages(chatID: Int) -> [ConversationFixture.Message] {
        [
            .text(id: 1, chatID: chatID, offset: 1, text: "First shared message", isFromMe: true),
            .text(id: 2, chatID: chatID, offset: 2, text: "Second shared message", isFromMe: false, author: author(phone: "34600000002")),
            .text(id: 3, chatID: chatID, offset: 3, text: "Third shared message", isFromMe: true)
        ]
    }

    private func author(phone: String) -> MessageAuthor {
        MessageAuthor(
            kind: .participant,
            displayName: nil,
            phone: phone,
            jid: "\(phone)@s.whatsapp.net",
            source: .messageJid
        )
    }
}

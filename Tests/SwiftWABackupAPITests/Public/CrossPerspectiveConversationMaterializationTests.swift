import Foundation
import XCTest
@testable import SwiftWABackupAPI

final class CrossPerspectiveConversationMaterializationTests: XCTestCase {
    func testOppositeIndividualPerspectivesAreMaterializedRelativeToTarget() throws {
        let fixture = try ConversationFixture()
        defer { fixture.remove() }
        let target = try fixture.source(
            id: "target",
            chatID: 10,
            jid: "34600000002@s.whatsapp.net",
            name: "B",
            archived: true,
            messages: [
                .text(id: 1, chatID: 10, offset: 1, text: "First shared message", isFromMe: true),
                .text(id: 2, chatID: 10, offset: 2, text: "Second shared message", isFromMe: false),
                .text(id: 3, chatID: 10, offset: 3, text: "Third shared message", isFromMe: true),
                .text(id: 4, chatID: 10, offset: 4, text: "Target-only message", isFromMe: true)
            ]
        )
        var sourceReply = ConversationFixture.Message.text(
            id: 15,
            chatID: 20,
            offset: 6,
            text: "Source incoming reply",
            isFromMe: false
        )
        sourceReply.replyTo = 14
        sourceReply.replyToPreview = "Source-only message"
        let source = try fixture.source(
            id: "source",
            chatID: 20,
            jid: "34600000001@s.whatsapp.net",
            name: "A",
            messages: [
                .text(id: 11, chatID: 20, offset: 1, text: "First shared message", isFromMe: false),
                .text(id: 12, chatID: 20, offset: 2, text: "Second shared message", isFromMe: true),
                .text(id: 13, chatID: 20, offset: 3, text: "Third shared message", isFromMe: false),
                .text(id: 14, chatID: 20, offset: 5, text: "Source-only message", isFromMe: true),
                sourceReply
            ]
        )
        let destination = fixture.root.appendingPathComponent("individual-output")

        let result = try engine().compose(
            sources: [source, target],
            targetSourceID: target.id,
            perspectiveConstraints: [],
            targetChatID: 99,
            destinationDirectory: destination
        )

        XCTAssertEqual(result.document.chat.id, 99)
        XCTAssertEqual(result.document.chat.contactJid, "34600000002@s.whatsapp.net")
        XCTAssertEqual(result.document.chat.name, "B")
        XCTAssertTrue(result.document.chat.isArchived)
        XCTAssertEqual(result.document.messages.count, 6)
        XCTAssertEqual(
            result.document.messages.map(\.message),
            [
                "First shared message",
                "Second shared message",
                "Third shared message",
                "Target-only message",
                "Source-only message",
                "Source incoming reply"
            ]
        )
        XCTAssertEqual(
            result.document.messages.map(\.isFromMe),
            [true, false, true, true, false, true]
        )
        XCTAssertEqual(result.document.messages[4].author?.kind, .participant)
        XCTAssertEqual(result.document.messages[4].author?.phone, "34600000002")
        XCTAssertEqual(result.document.messages[5].author?.kind, .me)
        XCTAssertEqual(result.document.messages[5].replyTo, 5)
        XCTAssertEqual(result.sourceImpacts.map(\.sharedMessageCount), [3, 3])
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.documentURL.path))
    }

    func testOppositeGroupPerspectiveOrientsOwnerAndOtherParticipants() throws {
        let fixture = try ConversationFixture()
        defer { fixture.remove() }
        let authorA = participant("34600000001", name: "A")
        let authorB = participant("34600000002", name: "B")
        let authorC = participant("34600000003", name: "C")
        let target = try fixture.source(
            id: "target",
            chatID: 1,
            jid: "family@g.us",
            name: "Target family",
            messages: [
                .text(id: 1, chatID: 1, offset: 1, text: "First group shared", isFromMe: true),
                .text(id: 2, chatID: 1, offset: 2, text: "Second group shared", isFromMe: false, author: authorB),
                .text(id: 3, chatID: 1, offset: 3, text: "Third group shared", isFromMe: true)
            ]
        )
        let source = try fixture.source(
            id: "source",
            chatID: 2,
            jid: "family@g.us",
            messages: [
                .text(id: 11, chatID: 2, offset: 1, text: "First group shared", isFromMe: false, author: authorA),
                .text(id: 12, chatID: 2, offset: 2, text: "Second group shared", isFromMe: true),
                .text(id: 13, chatID: 2, offset: 3, text: "Third group shared", isFromMe: false, author: authorA),
                .text(id: 14, chatID: 2, offset: 4, text: "Exclusive from B", isFromMe: true),
                .text(id: 15, chatID: 2, offset: 5, text: "Exclusive from A", isFromMe: false, author: authorA),
                .text(id: 16, chatID: 2, offset: 6, text: "Exclusive from C", isFromMe: false, author: authorC)
            ]
        )

        let result = try engine().compose(
            sources: [target, source],
            targetSourceID: target.id,
            perspectiveConstraints: [],
            targetChatID: 7,
            destinationDirectory: fixture.root.appendingPathComponent("group-output")
        )

        XCTAssertEqual(result.document.messages.count, 6)
        XCTAssertEqual(result.document.messages.map(\.isFromMe), [true, false, true, false, true, false])
        XCTAssertEqual(result.document.messages[3].author?.phone, "34600000002")
        XCTAssertEqual(result.document.messages[4].author?.kind, .me)
        XCTAssertEqual(result.document.messages[5].author?.phone, "34600000003")
        XCTAssertEqual(result.document.chat.name, "Target family")
    }

    func testNaryMixedPerspectivesAreDeterministicAcrossInputOrder() throws {
        let fixture = try ConversationFixture()
        defer { fixture.remove() }
        let authorA = participant("34600000001")
        let authorB = participant("34600000002")
        let targetMessages: [ConversationFixture.Message] = [
            .text(id: 1, chatID: 1, offset: 1, text: "Nary first shared", isFromMe: true),
            .text(id: 2, chatID: 1, offset: 2, text: "Nary second shared", isFromMe: false, author: authorB),
            .text(id: 3, chatID: 1, offset: 3, text: "Nary third shared", isFromMe: true)
        ]
        let target = try fixture.source(
            id: "target",
            chatID: 1,
            jid: "family@g.us",
            messages: targetMessages
        )
        let same = try fixture.source(
            id: "same",
            chatID: 2,
            jid: "family@g.us",
            messages: [
                .text(id: 21, chatID: 2, offset: 1, text: "Nary first shared", isFromMe: true),
                .text(id: 22, chatID: 2, offset: 2, text: "Nary second shared", isFromMe: false, author: authorB),
                .text(id: 23, chatID: 2, offset: 3, text: "Nary third shared", isFromMe: true),
                .text(id: 24, chatID: 2, offset: 4, text: "Exclusive from target perspective", isFromMe: true)
            ]
        )
        let opposite = try fixture.source(
            id: "opposite",
            chatID: 3,
            jid: "family@g.us",
            messages: [
                .text(id: 31, chatID: 3, offset: 1, text: "Nary first shared", isFromMe: false, author: authorA),
                .text(id: 32, chatID: 3, offset: 2, text: "Nary second shared", isFromMe: true),
                .text(id: 33, chatID: 3, offset: 3, text: "Nary third shared", isFromMe: false, author: authorA),
                .text(id: 34, chatID: 3, offset: 5, text: "Exclusive from opposite perspective", isFromMe: true)
            ]
        )

        let first = try engine().compose(
            sources: [opposite, target, same],
            targetSourceID: target.id,
            perspectiveConstraints: [],
            targetChatID: 5,
            destinationDirectory: fixture.root.appendingPathComponent("nary-first")
        )
        let second = try engine().compose(
            sources: [same, opposite, target],
            targetSourceID: target.id,
            perspectiveConstraints: [],
            targetChatID: 5,
            destinationDirectory: fixture.root.appendingPathComponent("nary-second")
        )

        XCTAssertEqual(first.document.messages.count, 5)
        XCTAssertEqual(first.document.messages.map(\.message), second.document.messages.map(\.message))
        XCTAssertEqual(first.document.messages.map(\.isFromMe), [true, false, true, true, false])
        XCTAssertEqual(
            first.stableMessageIDsByMaterializedID,
            second.stableMessageIDsByMaterializedID
        )
        XCTAssertEqual(first.sourceImpacts.count, 3)
        XCTAssertEqual(first.sourceImpacts.map(\.sharedMessageCount), [3, 3, 3])
    }

    func testUniqueWeakMessageBetweenStrongAnchorsIsDeduplicated() throws {
        let fixture = try ConversationFixture()
        defer { fixture.remove() }
        let target = try fixture.source(
            id: "target",
            chatID: 1,
            messages: sharedMessages(chatID: 1) + [
                .text(id: 4, chatID: 1, offset: 4, text: "OK", isFromMe: true)
            ]
        )
        let source = try fixture.source(
            id: "source",
            chatID: 2,
            messages: sharedMessages(chatID: 2) + [
                .text(id: 14, chatID: 2, offset: 4, text: "OK", isFromMe: true)
            ]
        )

        let prepared = try engine().analyze(
            sources: [target, source],
            targetSourceID: target.id,
            perspectiveConstraints: []
        )

        XCTAssertEqual(prepared.plan.statistics.inputMessageCount, 8)
        XCTAssertEqual(prepared.plan.statistics.materializedMessageCount, 4)
        XCTAssertEqual(prepared.plan.statistics.sharedLogicalMessageCount, 4)
        XCTAssertEqual(prepared.plan.algorithmVersion, 2)
        XCTAssertNotNil(prepared.plan.crossPerspectiveDiagnostic)
        let encodedPlan = try JSONEncoder().encode(prepared.plan)
        let decodedPlan = try JSONDecoder().decode(
            ConversationCompositionPlan.self,
            from: encodedPlan
        )
        XCTAssertEqual(decodedPlan.profile, .conservativeCrossPerspective)
        XCTAssertEqual(decodedPlan.crossPerspectiveDiagnostic?.disposition, .applicable)
    }

    func testSystematicTimestampOffsetNormalizesExclusiveMessages() throws {
        let fixture = try ConversationFixture()
        defer { fixture.remove() }
        let target = try fixture.source(id: "target", chatID: 1, messages: sharedMessages(chatID: 1))
        let source = try fixture.source(
            id: "source",
            chatID: 2,
            messages: [
                .text(id: 11, chatID: 2, offset: 11, text: "First shared message", isFromMe: true),
                .text(id: 12, chatID: 2, offset: 12, text: "Second shared message", isFromMe: false, author: participant("34600000002")),
                .text(id: 13, chatID: 2, offset: 13, text: "Third shared message", isFromMe: true),
                .text(id: 14, chatID: 2, offset: 14, text: "Exclusive after offset", isFromMe: true)
            ]
        )
        let offsetPolicy = ConversationCompositionPolicy(
            profile: .conservativeCrossPerspective,
            maximumTimestampDifferenceMilliseconds: 1_000,
            minimumStrongAnchorCount: 3,
            minimumOverlapMessageCount: 3,
            minimumOrderConsistency: 0.9,
            allowSystematicTimestampOffset: true
        )

        let result = try ConversationCompositionEngine(policy: offsetPolicy).compose(
            sources: [target, source],
            targetSourceID: target.id,
            perspectiveConstraints: [],
            targetChatID: 3,
            destinationDirectory: fixture.root.appendingPathComponent("offset-output")
        )

        XCTAssertEqual(result.document.messages.last?.message, "Exclusive after offset")
        XCTAssertEqual(
            result.document.messages.last?.date,
            ConversationFixture.baseDate.addingTimeInterval(4)
        )
    }

    func testOppositeIndividualCopiesMediaAndReorientsReactions() throws {
        let fixture = try ConversationFixture()
        defer { fixture.remove() }
        let target = try fixture.source(
            id: "target",
            chatID: 1,
            jid: "34600000002@s.whatsapp.net",
            messages: [
                .text(id: 1, chatID: 1, offset: 1, text: "First shared media case", isFromMe: true),
                .text(id: 2, chatID: 1, offset: 2, text: "Second shared media case", isFromMe: false),
                .text(id: 3, chatID: 1, offset: 3, text: "Third shared media case", isFromMe: true)
            ]
        )
        var mediaMessage = ConversationFixture.Message.media(
            id: 14,
            chatID: 2,
            offset: 4,
            filename: "received.bin"
        )
        mediaMessage.reactions = [
            Reaction(
                emoji: "👍",
                author: MessageAuthor(
                    kind: .me,
                    displayName: nil,
                    phone: nil,
                    jid: nil,
                    source: .owner
                )
            ),
            Reaction(emoji: "❤️", author: participant("34600000001"))
        ]
        let source = try fixture.source(
            id: "source",
            chatID: 2,
            jid: "34600000001@s.whatsapp.net",
            messages: [
                .text(id: 11, chatID: 2, offset: 1, text: "First shared media case", isFromMe: false),
                .text(id: 12, chatID: 2, offset: 2, text: "Second shared media case", isFromMe: true),
                .text(id: 13, chatID: 2, offset: 3, text: "Third shared media case", isFromMe: false),
                mediaMessage
            ],
            media: ["received.bin": Data("cross-perspective-media".utf8)]
        )

        let result = try engine().compose(
            sources: [target, source],
            targetSourceID: target.id,
            perspectiveConstraints: [],
            targetChatID: 4,
            destinationDirectory: fixture.root.appendingPathComponent("media-output")
        )

        let materialized = try XCTUnwrap(result.document.messages.last)
        let mediaFilename = try XCTUnwrap(materialized.mediaFilename)
        XCTAssertFalse(materialized.isFromMe)
        XCTAssertEqual(materialized.author?.phone, "34600000002")
        XCTAssertEqual(materialized.reactions?.map(\.author.kind), [.participant, .me])
        XCTAssertEqual(
            try Data(contentsOf: result.mediaDirectoryURL.appendingPathComponent(mediaFilename)),
            Data("cross-perspective-media".utf8)
        )
    }

    func testRejectedCompositionDoesNotCreateDestination() throws {
        let fixture = try ConversationFixture()
        defer { fixture.remove() }
        let target = try fixture.source(
            id: "target",
            chatID: 1,
            messages: [.text(id: 1, chatID: 1, offset: 1, text: "Only one shared message")]
        )
        let source = try fixture.source(
            id: "source",
            chatID: 2,
            messages: [.text(id: 2, chatID: 2, offset: 1, text: "Only one shared message")]
        )
        let destination = fixture.root.appendingPathComponent("must-not-exist")

        XCTAssertThrowsError(
            try engine().compose(
                sources: [target, source],
                targetSourceID: target.id,
                perspectiveConstraints: [],
                targetChatID: 3,
                destinationDirectory: destination
            )
        ) { error in
            guard case ConversationCompositionError.crossPerspectiveCompositionRejected(
                let diagnostic
            ) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(diagnostic.disposition, .rejected)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    private func engine() -> ConversationCompositionEngine {
        let policy = ConversationCompositionPolicy(
            profile: .conservativeCrossPerspective,
            maximumTimestampDifferenceMilliseconds: 1_000,
            minimumStrongAnchorCount: 3,
            minimumOverlapMessageCount: 3,
            minimumOrderConsistency: 0.9
        )
        return ConversationCompositionEngine(policy: policy)
    }

    private func sharedMessages(chatID: Int) -> [ConversationFixture.Message] {
        [
            .text(id: 1, chatID: chatID, offset: 1, text: "First shared message", isFromMe: true),
            .text(id: 2, chatID: chatID, offset: 2, text: "Second shared message", isFromMe: false, author: participant("34600000002")),
            .text(id: 3, chatID: chatID, offset: 3, text: "Third shared message", isFromMe: true)
        ]
    }

    private func participant(_ phone: String, name: String? = nil) -> MessageAuthor {
        MessageAuthor(
            kind: .participant,
            displayName: name,
            phone: phone,
            jid: "\(phone)@s.whatsapp.net",
            source: .messageJid
        )
    }
}

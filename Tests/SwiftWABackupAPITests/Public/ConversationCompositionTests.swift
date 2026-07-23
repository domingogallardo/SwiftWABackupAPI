import Foundation
import XCTest
@testable import SwiftWABackupAPI

final class ConversationCompositionTests: XCTestCase {
    func testSHA256MatchesPublishedVectors() {
        XCTAssertEqual(
            ConversationSHA256.hashHex(Data()),
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        )
        XCTAssertEqual(
            ConversationSHA256.hashHex(Data("abc".utf8)),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
        var chunked = ConversationSHA256()
        chunked.update(data: Data("a".utf8))
        chunked.update(data: Data("b".utf8))
        chunked.update(data: Data("c".utf8))
        XCTAssertEqual(
            chunked.finalizeHex(),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
    }

    func testAnalyzeRejectsMissingSourcesTargetConstraintAndDuplicates() throws {
        let fixture = try ConversationFixture()
        defer { fixture.remove() }
        let source = try fixture.source(id: "one", chatID: 1, messages: [])
        let engine = ConversationCompositionEngine()

        XCTAssertThrowsError(
            try engine.analyze(
                sources: [],
                targetSourceID: source.id,
                perspectiveConstraints: []
            )
        ) { error in
            guard case ConversationCompositionError.noSources = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        XCTAssertThrowsError(
            try engine.analyze(
                sources: [source],
                targetSourceID: ConversationSourceID(rawValue: "missing"),
                perspectiveConstraints: [.samePerspective(sourceIDs: [source.id])]
            )
        ) { error in
            guard case ConversationCompositionError.targetSourceNotFound = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        XCTAssertThrowsError(
            try engine.analyze(
                sources: [source],
                targetSourceID: source.id,
                perspectiveConstraints: []
            )
        ) { error in
            guard case ConversationCompositionError.missingSamePerspectiveConstraint = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        XCTAssertThrowsError(
            try engine.analyze(
                sources: [source, source],
                targetSourceID: source.id,
                perspectiveConstraints: [.samePerspective(sourceIDs: [source.id])]
            )
        ) { error in
            guard case ConversationCompositionError.duplicateSourceID = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testGroupIdentityUsesJIDAndNotDisplayName() throws {
        let fixture = try ConversationFixture()
        defer { fixture.remove() }
        let first = try fixture.source(
            id: "first",
            chatID: 1,
            jid: "100@g.us",
            name: "Same name",
            messages: []
        )
        let second = try fixture.source(
            id: "second",
            chatID: 2,
            jid: "200@g.us",
            name: "Same name",
            messages: []
        )

        XCTAssertThrowsError(
            try ConversationCompositionEngine().analyze(
                sources: [first, second],
                targetSourceID: first.id,
                perspectiveConstraints: [.samePerspective(sourceIDs: [first.id, second.id])]
            )
        ) { error in
            guard case ConversationCompositionError.differentConversations = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testIndividualPhoneAndLIDCanMatchThroughExplicitCounterpartAlias() throws {
        let fixture = try ConversationFixture()
        defer { fixture.remove() }
        let aliases = CanonicalParticipantIdentity(
            addresses: [
                ParticipantAddress(kind: .phoneJID, value: "34600000000@s.whatsapp.net"),
                ParticipantAddress(kind: .lidJID, value: "998877@lid")
            ]
        )
        let phone = try fixture.source(
            id: "phone",
            chatID: 1,
            jid: "34600000000@s.whatsapp.net",
            messages: [],
            conversationIdentityHint: aliases
        )
        let lid = try fixture.source(
            id: "lid",
            chatID: 2,
            jid: "998877@lid",
            messages: [],
            conversationIdentityHint: aliases
        )

        let plan = try ConversationCompositionEngine().analyze(
            sources: [phone, lid],
            targetSourceID: phone.id,
            perspectiveConstraints: [.samePerspective(sourceIDs: [phone.id, lid.id])]
        ).plan
        XCTAssertEqual(plan.statistics.sourceCount, 2)
        XCTAssertEqual(plan.confidence, .high)
    }

    func testOverlapIsDeduplicatedAndRemovalImpactIsNary() throws {
        let fixture = try ConversationFixture()
        defer { fixture.remove() }
        let a = try fixture.source(
            id: "a",
            chatID: 10,
            messages: [
                .text(id: 1, chatID: 10, offset: 1, text: "A"),
                .text(id: 2, chatID: 10, offset: 2, text: "B"),
                .text(id: 3, chatID: 10, offset: 3, text: "C")
            ]
        )
        let b = try fixture.source(
            id: "b",
            chatID: 20,
            messages: [
                .text(id: 20, chatID: 20, offset: 2, text: "B"),
                .text(id: 30, chatID: 20, offset: 3, text: "C"),
                .text(id: 40, chatID: 20, offset: 4, text: "D")
            ]
        )
        let c = try fixture.source(
            id: "c",
            chatID: 30,
            messages: [
                .text(id: 300, chatID: 30, offset: 3, text: "C"),
                .text(id: 400, chatID: 30, offset: 4, text: "D"),
                .text(id: 500, chatID: 30, offset: 5, text: "E")
            ]
        )
        let ids = [a.id, b.id, c.id]
        let prepared = try ConversationCompositionEngine().analyze(
            sources: [a, b, c],
            targetSourceID: c.id,
            perspectiveConstraints: [.samePerspective(sourceIDs: ids)]
        )

        XCTAssertEqual(prepared.plan.statistics.inputMessageCount, 9)
        XCTAssertEqual(prepared.plan.statistics.materializedMessageCount, 5)
        XCTAssertEqual(prepared.plan.statistics.deduplicatedOccurrenceCount, 4)
        XCTAssertEqual(prepared.plan.statistics.sharedLogicalMessageCount, 3)
        XCTAssertEqual(prepared.plan.sourceImpacts.map(\.exclusiveMessageCount), [1, 0, 1])
        let removal = try prepared.plan.removalImpact(of: b.id)
        XCTAssertEqual(removal.removedMessageCount, 0)
        XCTAssertEqual(removal.resultingMessageCount, 5)
    }

    func testCanonicalTextNormalizationDeduplicatesNFCAndLineEndingsOnly() throws {
        let fixture = try ConversationFixture()
        defer { fixture.remove() }
        let composed = "café\nline"
        let decomposed = "cafe\u{301}\r\nline"
        let a = try fixture.source(
            id: "a",
            chatID: 1,
            messages: [.text(id: 1, chatID: 1, offset: 1, text: composed)]
        )
        let b = try fixture.source(
            id: "b",
            chatID: 2,
            messages: [
                .text(id: 2, chatID: 2, offset: 1, text: decomposed),
                .text(id: 3, chatID: 2, offset: 1, text: composed + " ")
            ]
        )
        let plan = try ConversationCompositionEngine().analyze(
            sources: [a, b],
            targetSourceID: a.id,
            perspectiveConstraints: [.samePerspective(sourceIDs: [a.id, b.id])]
        ).plan
        XCTAssertEqual(plan.statistics.materializedMessageCount, 2)
        XCTAssertEqual(plan.statistics.deduplicatedOccurrenceCount, 1)
    }

    func testDuplicateWithinSourceIsCollapsedAndDiagnosed() throws {
        let fixture = try ConversationFixture()
        defer { fixture.remove() }
        let source = try fixture.source(
            id: "source",
            chatID: 1,
            messages: [
                .text(id: 1, chatID: 1, offset: 1, text: "same"),
                .text(id: 2, chatID: 1, offset: 1, text: "same")
            ]
        )
        let plan = try ConversationCompositionEngine().analyze(
            sources: [source],
            targetSourceID: source.id,
            perspectiveConstraints: [.samePerspective(sourceIDs: [source.id])]
        ).plan
        XCTAssertEqual(plan.statistics.materializedMessageCount, 1)
        XCTAssertTrue(plan.reasons.contains(.duplicateFingerprintWithinSource))
    }

    func testMaterializationRemapsRepliesUsesTargetMetadataAndStableIDs() throws {
        let fixture = try ConversationFixture()
        defer { fixture.remove() }
        let stableTarget = ArchiveMessageID(
            rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        )
        let stableOther = ArchiveMessageID(
            rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        )
        var reply = ConversationFixture.Message.text(
            id: 22,
            chatID: 2,
            offset: 2,
            text: "reply"
        )
        reply.replyTo = 11
        reply.replyToPreview = "first"
        let target = try fixture.source(
            id: "target",
            chatID: 2,
            name: "Newest",
            archived: true,
            messages: [
                .text(id: 11, chatID: 2, offset: 1, text: "first"),
                reply
            ],
            stableMessageIDs: [11: stableTarget]
        )
        let other = try fixture.source(
            id: "other",
            chatID: 1,
            name: "Older",
            messages: [.text(id: 1, chatID: 1, offset: 1, text: "first")],
            stableMessageIDs: [1: stableOther]
        )
        let resultDirectory = fixture.root.appendingPathComponent("result")
        let result = try ConversationCompositionEngine().compose(
            sources: [other, target],
            targetSourceID: target.id,
            perspectiveConstraints: [.samePerspective(sourceIDs: [other.id, target.id])],
            targetChatID: 99,
            destinationDirectory: resultDirectory
        )

        XCTAssertEqual(result.document.chat.id, 99)
        XCTAssertEqual(result.document.chat.name, "Newest")
        XCTAssertTrue(result.document.chat.isArchived)
        XCTAssertEqual(result.document.messages.map(\.id), [1, 2])
        XCTAssertEqual(result.document.messages.map(\.chatId), [99, 99])
        XCTAssertEqual(result.document.messages[1].replyTo, 1)
        XCTAssertEqual(result.stableMessageIDsByMaterializedID[1], stableTarget)
        XCTAssertEqual(result.sourceMappings.first {
            $0.sourceID == other.id
        }?.sourceMessageIDs[1], stableTarget)
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.documentURL.path))
    }

    func testStableIDCannotIdentifyDifferentLogicalMessages() throws {
        let fixture = try ConversationFixture()
        defer { fixture.remove() }
        let stable = ArchiveMessageID(
            rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000010")!
        )
        let a = try fixture.source(
            id: "a",
            chatID: 1,
            messages: [.text(id: 1, chatID: 1, offset: 1, text: "A")],
            stableMessageIDs: [1: stable]
        )
        let b = try fixture.source(
            id: "b",
            chatID: 2,
            messages: [.text(id: 2, chatID: 2, offset: 2, text: "B")],
            stableMessageIDs: [2: stable]
        )
        XCTAssertThrowsError(
            try ConversationCompositionEngine().analyze(
                sources: [a, b],
                targetSourceID: a.id,
                perspectiveConstraints: [.samePerspective(sourceIDs: [a.id, b.id])]
            )
        ) { error in
            guard case ConversationCompositionError.incompatibleStableMessageID = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testMediaIsDeduplicatedByContentAndSameNamesWithDifferentContentSurvive() throws {
        let fixture = try ConversationFixture()
        defer { fixture.remove() }
        let first = try fixture.source(
            id: "first",
            chatID: 1,
            messages: [
                .media(id: 1, chatID: 1, offset: 1, filename: "first.bin"),
                .media(id: 2, chatID: 1, offset: 2, filename: "collision.bin")
            ],
            media: [
                "first.bin": Data("shared".utf8),
                "collision.bin": Data("one".utf8)
            ]
        )
        let target = try fixture.source(
            id: "target",
            chatID: 2,
            messages: [
                .media(id: 10, chatID: 2, offset: 1, filename: "renamed.bin"),
                .media(id: 20, chatID: 2, offset: 3, filename: "collision.bin")
            ],
            media: [
                "renamed.bin": Data("shared".utf8),
                "collision.bin": Data("two".utf8)
            ]
        )
        let destination = fixture.root.appendingPathComponent("materialized")
        let result = try ConversationCompositionEngine().compose(
            sources: [first, target],
            targetSourceID: target.id,
            perspectiveConstraints: [.samePerspective(sourceIDs: [first.id, target.id])],
            targetChatID: 50,
            destinationDirectory: destination
        )

        XCTAssertEqual(result.document.messages.count, 3)
        XCTAssertEqual(Set(result.document.messages.compactMap(\.mediaFilename)).count, 3)
        XCTAssertEqual(result.statistics.copiedMediaFileCount, 3)
        XCTAssertEqual(result.document.chat.mediaByteCount, Int64(6 + 3 + 3))
        let files = try FileManager.default.contentsOfDirectory(atPath: result.mediaDirectoryURL.path)
        XCTAssertEqual(files.count, 3)
        XCTAssertEqual(result.document.messages.first?.mediaFilename?.suffix(10), "-first.bin")
    }

    func testMaterializationDetectsChangedInputAndDoesNotLeaveCreatedDestination() throws {
        let fixture = try ConversationFixture()
        defer { fixture.remove() }
        let source = try fixture.source(
            id: "source",
            chatID: 1,
            messages: [.media(id: 1, chatID: 1, offset: 1, filename: "media.bin")],
            media: ["media.bin": Data("before".utf8)]
        )
        let engine = ConversationCompositionEngine()
        let prepared = try engine.analyze(
            sources: [source],
            targetSourceID: source.id,
            perspectiveConstraints: [.samePerspective(sourceIDs: [source.id])]
        )
        try Data("after-with-different-size".utf8).write(
            to: source.mediaDirectoryURL.appendingPathComponent("media.bin")
        )
        let destination = fixture.root.appendingPathComponent("changed-result")
        XCTAssertThrowsError(
            try engine.materialize(
                prepared,
                targetChatID: 1,
                destinationDirectory: destination
            )
        ) { error in
            guard case ConversationCompositionError.inputChanged = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    func testComposeEmitsOneCompletionAndCancellationLeavesNoOutput() throws {
        let fixture = try ConversationFixture()
        defer { fixture.remove() }
        let source = try fixture.source(
            id: "source",
            chatID: 1,
            messages: [.text(id: 1, chatID: 1, offset: 1, text: "A")]
        )
        var events: [WABackupProgress] = []
        let destination = fixture.root.appendingPathComponent("progress-result")
        _ = try ConversationCompositionEngine().compose(
            sources: [source],
            targetSourceID: source.id,
            perspectiveConstraints: [.samePerspective(sourceIDs: [source.id])],
            targetChatID: 1,
            destinationDirectory: destination,
            progress: { events.append($0) }
        )
        XCTAssertEqual(events.filter { $0.phase == .completed }.count, 1)
        XCTAssertTrue(events.contains { $0.phase == .canonicalizingConversationMessages })
        XCTAssertTrue(events.allSatisfy { $0.currentItem == nil })
        var previousByPhase: [String: Int] = [:]
        for event in events {
            XCTAssertGreaterThanOrEqual(
                event.completedUnitCount,
                previousByPhase[event.phase.rawValue] ?? 0,
                "Progress went backwards for \(event.phase)."
            )
            previousByPhase[event.phase.rawValue] = event.completedUnitCount
        }

        let cancelledDestination = fixture.root.appendingPathComponent("cancelled-result")
        XCTAssertThrowsError(
            try ConversationCompositionEngine().compose(
                sources: [source],
                targetSourceID: source.id,
                perspectiveConstraints: [.samePerspective(sourceIDs: [source.id])],
                targetChatID: 1,
                destinationDirectory: cancelledDestination,
                cancellation: { true }
            )
        ) { error in
            guard case ConversationCompositionError.cancelled = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: cancelledDestination.path))
    }

    func testUnsafeMediaSymlinkAndNonemptyDestinationAreRejected() throws {
        let fixture = try ConversationFixture()
        defer { fixture.remove() }
        let unsafe = try fixture.source(
            id: "unsafe",
            chatID: 1,
            messages: [.media(id: 1, chatID: 1, offset: 1, filename: "../escape.bin")]
        )
        XCTAssertThrowsError(
            try ConversationCompositionEngine().analyze(
                sources: [unsafe],
                targetSourceID: unsafe.id,
                perspectiveConstraints: [.samePerspective(sourceIDs: [unsafe.id])]
            )
        ) { error in
            guard case ConversationCompositionError.invalidSource = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }

        let symlink = try fixture.source(
            id: "symlink",
            chatID: 2,
            messages: [.media(id: 2, chatID: 2, offset: 1, filename: "linked.bin")],
            media: ["linked.bin": Data("placeholder".utf8)]
        )
        let outside = fixture.root.appendingPathComponent("outside.bin")
        try Data("outside".utf8).write(to: outside)
        let linked = symlink.mediaDirectoryURL.appendingPathComponent("linked.bin")
        try FileManager.default.removeItem(at: linked)
        try FileManager.default.createSymbolicLink(at: linked, withDestinationURL: outside)
        XCTAssertThrowsError(
            try ConversationCompositionEngine().analyze(
                sources: [symlink],
                targetSourceID: symlink.id,
                perspectiveConstraints: [.samePerspective(sourceIDs: [symlink.id])]
            )
        ) { error in
            guard case ConversationCompositionError.invalidSource = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }

        let valid = try fixture.source(
            id: "valid",
            chatID: 3,
            messages: [.text(id: 3, chatID: 3, offset: 1, text: "valid")]
        )
        let prepared = try ConversationCompositionEngine().analyze(
            sources: [valid],
            targetSourceID: valid.id,
            perspectiveConstraints: [.samePerspective(sourceIDs: [valid.id])]
        )
        let destination = fixture.root.appendingPathComponent("nonempty", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try Data().write(to: destination.appendingPathComponent("keep"))
        XCTAssertThrowsError(
            try ConversationCompositionEngine().materialize(
                prepared,
                targetChatID: 3,
                destinationDirectory: destination
            )
        ) { error in
            guard case ConversationCompositionError.destinationNotEmpty = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.appendingPathComponent("keep").path))
    }

    func testLargeSyntheticCompositionIsLinearEnoughForInteractiveUse() throws {
        let fixture = try ConversationFixture()
        defer { fixture.remove() }
        let count = 10_000
        let firstMessages = (0..<count).map {
            ConversationFixture.Message.text(
                id: $0 + 1,
                chatID: 1,
                offset: $0,
                text: "message-\($0)"
            )
        }
        let secondMessages = (count / 2..<(count + count / 2)).map {
            ConversationFixture.Message.text(
                id: $0 + 10_001,
                chatID: 2,
                offset: $0,
                text: "message-\($0)"
            )
        }
        let first = try fixture.source(id: "first", chatID: 1, messages: firstMessages)
        let second = try fixture.source(id: "second", chatID: 2, messages: secondMessages)
        let started = Date()
        let plan = try ConversationCompositionEngine().analyze(
            sources: [first, second],
            targetSourceID: second.id,
            perspectiveConstraints: [.samePerspective(sourceIDs: [first.id, second.id])]
        ).plan
        let elapsed = Date().timeIntervalSince(started)

        XCTAssertEqual(plan.statistics.inputMessageCount, 20_000)
        XCTAssertEqual(plan.statistics.materializedMessageCount, 15_000)
        XCTAssertLessThan(elapsed, 20)
    }
}

final class ConversationFixture {
    struct Message {
        let id: Int
        let chatID: Int
        let offset: Int
        let text: String?
        let isFromMe: Bool
        let messageType: String
        let author: MessageAuthor?
        var caption: String?
        var replyTo: Int?
        var replyToPreview: String?
        let mediaFilename: String?
        var reactions: [Reaction]?

        static func text(
            id: Int,
            chatID: Int,
            offset: Int,
            text: String,
            isFromMe: Bool = true,
            author: MessageAuthor? = nil
        ) -> Self {
            Self(
                id: id,
                chatID: chatID,
                offset: offset,
                text: text,
                isFromMe: isFromMe,
                messageType: "Text",
                author: author,
                caption: nil,
                replyTo: nil,
                replyToPreview: nil,
                mediaFilename: nil,
                reactions: nil
            )
        }

        static func media(id: Int, chatID: Int, offset: Int, filename: String) -> Self {
            Self(
                id: id,
                chatID: chatID,
                offset: offset,
                text: nil,
                isFromMe: true,
                messageType: "Document",
                author: nil,
                caption: nil,
                replyTo: nil,
                replyToPreview: nil,
                mediaFilename: filename,
                reactions: nil
            )
        }
    }

    static let baseDate = Date(timeIntervalSince1970: 1_700_000_000)

    let root: URL
    private var sourceIndex = 0

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "SwiftWABackupAPI-CompositionTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }

    func source(
        id: String,
        chatID: Int,
        jid: String = "100@g.us",
        name: String = "Conversation",
        archived: Bool = false,
        messages specifications: [Message],
        media: [String: Data] = [:],
        contacts: [ContactInfo] = [],
        conversationIdentityHint: CanonicalParticipantIdentity? = nil,
        perspectiveHint: ConversationPerspectiveHint? = nil,
        stableMessageIDs: [Int: ArchiveMessageID] = [:]
    ) throws -> ConversationSource {
        sourceIndex += 1
        let directory = root.appendingPathComponent("source-\(sourceIndex)", isDirectory: true)
        let mediaDirectory = directory.appendingPathComponent("Media", isDirectory: true)
        try FileManager.default.createDirectory(at: mediaDirectory, withIntermediateDirectories: true)
        for (filename, data) in media {
            try data.write(to: mediaDirectory.appendingPathComponent(filename))
        }

        let messages = specifications.map { specification -> MessageInfo in
            var message = MessageInfo(
                id: specification.id,
                chatId: specification.chatID,
                message: specification.text,
                date: Self.baseDate.addingTimeInterval(Double(specification.offset)),
                isFromMe: specification.isFromMe,
                messageType: specification.messageType,
                author: specification.author
            )
            message.caption = specification.caption
            message.replyTo = specification.replyTo
            message.replyToPreview = specification.replyToPreview
            message.mediaFilename = specification.mediaFilename
            message.reactions = specification.reactions
            return message
        }
        let lastMessageDate = messages.last?.date ?? Self.baseDate
        let chat = ChatInfo(
            id: chatID,
            contactJid: jid,
            name: name,
            numberMessages: messages.count,
            lastMessageDate: lastMessageDate,
            isArchived: archived,
            mediaByteCount: Int64(media.values.reduce(0) { $0 + $1.count })
        )
        let document = ExportedChatDocument(
            payload: ChatDumpPayload(
                chatInfo: chat,
                messages: messages,
                contacts: contacts
            ),
            exportedAt: Self.baseDate.addingTimeInterval(Double(sourceIndex))
        )
        return try ConversationSource(
            id: ConversationSourceID(rawValue: id),
            document: document,
            mediaDirectoryURL: mediaDirectory,
            conversationIdentityHint: conversationIdentityHint,
            perspectiveHint: perspectiveHint,
            stableMessageIDs: stableMessageIDs
        )
    }
}

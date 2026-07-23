import Foundation
import XCTest
import ZIPFoundation
@testable import SwiftWABackupAPI

final class PortableConversationArchiveCodecTests: XCTestCase {
    private let producer = PortableArchiveProducer(
        name: "SwiftWABackupAPITests",
        version: "1.0"
    )

    func testGroupArchiveRoundTripPreservesPortableSemanticsAndComposes() throws {
        let fixture = try ConversationFixture()
        defer { fixture.remove() }
        let participant = participantAuthor("34600000002", name: "Member")
        var reply = ConversationFixture.Message.text(
            id: 3,
            chatID: 10,
            offset: 3,
            text: "Reply",
            isFromMe: true
        )
        reply.replyTo = 2
        reply.replyToPreview = "Incoming"
        reply.reactions = [
            Reaction(emoji: "👍", author: participant)
        ]
        let stableReply = ArchiveMessageID(
            rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
        )
        let source = try fixture.source(
            id: "original",
            chatID: 10,
            jid: "family@g.us",
            name: "Family",
            archived: true,
            messages: [
                .text(id: 1, chatID: 10, offset: 1, text: "Outgoing"),
                .text(
                    id: 2,
                    chatID: 10,
                    offset: 2,
                    text: "Incoming",
                    isFromMe: false,
                    author: participant
                ),
                reply
            ],
            stableMessageIDs: [3: stableReply]
        )
        let archiveURL = fixture.root.appendingPathComponent("family.fmcchat")
        let extractedURL = fixture.root.appendingPathComponent("extracted")
        let codec = PortableConversationArchiveCodec()

        let created = try codec.createArchive(
            from: source,
            producer: producer,
            destinationURL: archiveURL
        )
        var inspectionProgress: [WABackupProgress] = []
        let inspected = try codec.inspectArchive(
            at: archiveURL,
            progress: { inspectionProgress.append($0) }
        )
        let extracted = try codec.extractValidatedArchive(
            at: archiveURL,
            to: extractedURL
        )
        let imported = try extracted.makeConversationSource(
            id: ConversationSourceID(rawValue: "imported")
        )

        XCTAssertEqual(created.archiveSHA256, inspected.archiveSHA256)
        XCTAssertEqual(inspected.manifest.conversation.groupJID, "family@g.us")
        XCTAssertEqual(extracted.document.messages.count, 3)
        XCTAssertEqual(extracted.document.messages[0].author.role, .sourceUser)
        XCTAssertNil(extracted.document.messages[0].author.identityHint)
        XCTAssertEqual(extracted.document.messages[1].author.role, .participant)
        XCTAssertEqual(extracted.document.messages[2].replyTo, extracted.document.messages[1].id)
        XCTAssertEqual(extracted.document.messages[2].id, stableReply)
        XCTAssertEqual(extracted.document.messages[2].reactions?.first?.emoji, "👍")
        XCTAssertEqual(imported.kind, .portableDocument)
        let inspectedEntries = inspectionProgress.filter {
            $0.phase == .inspectingPortableConversationArchive
        }
        XCTAssertEqual(inspectedEntries.first?.completedUnitCount, 0)
        XCTAssertEqual(
            inspectedEntries.last?.completedUnitCount,
            inspectedEntries.last?.totalUnitCount
        )
        XCTAssertEqual(inspectionProgress.last?.phase, .completed)
        let chatJSON = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: Data(contentsOf: extracted.documentURL)
            ) as? [String: Any]
        )
        let encodedMessages = try XCTUnwrap(chatJSON["messages"] as? [[String: Any]])
        XCTAssertTrue(encodedMessages.allSatisfy { $0["id"] is String })
        XCTAssertTrue(encodedMessages[2]["replyTo"] is String)
        XCTAssertNil(chatJSON["sourceOwner"])

        let plan = try ConversationCompositionEngine().analyze(
            sources: [source, imported],
            targetSourceID: source.id,
            perspectiveConstraints: [
                .samePerspective(sourceIDs: [source.id, imported.id])
            ]
        ).plan
        XCTAssertEqual(plan.statistics.inputMessageCount, 6)
        XCTAssertEqual(plan.statistics.materializedMessageCount, 3)
    }

    func testIndividualArchiveDoesNotSerializeSourceUserIdentity() throws {
        let fixture = try ConversationFixture()
        defer { fixture.remove() }
        let owner = MessageAuthor(
            kind: .me,
            displayName: "Secret Owner Name",
            phone: "34611111111",
            jid: "34611111111@s.whatsapp.net",
            source: .owner
        )
        let source = try fixture.source(
            id: "individual",
            chatID: 20,
            jid: "34622222222@s.whatsapp.net",
            messages: [
                .text(
                    id: 1,
                    chatID: 20,
                    offset: 1,
                    text: "Hello",
                    isFromMe: true,
                    author: owner
                ),
                .text(
                    id: 2,
                    chatID: 20,
                    offset: 2,
                    text: "Hi",
                    isFromMe: false
                )
            ]
        )
        let archiveURL = fixture.root.appendingPathComponent("individual.fmcchat")
        let extractedURL = fixture.root.appendingPathComponent("individual")
        let codec = PortableConversationArchiveCodec()

        _ = try codec.createArchive(
            from: source,
            producer: producer,
            destinationURL: archiveURL
        )
        let extracted = try codec.extractValidatedArchive(
            at: archiveURL,
            to: extractedURL
        )
        let json = try String(
            contentsOf: extracted.documentURL,
            encoding: .utf8
        )

        XCTAssertFalse(json.contains("Secret Owner Name"))
        XCTAssertFalse(json.contains("34611111111"))
        XCTAssertEqual(extracted.document.messages[0].author.role, .sourceUser)
        XCTAssertNil(extracted.document.messages[0].author.identityHint)
        XCTAssertNil(extracted.document.messages[0].author.displayName)
        XCTAssertEqual(extracted.document.messages[1].author.role, .participant)
        XCTAssertTrue(
            extracted.document.messages[1].author.identityHint?.addresses.contains(
                ParticipantAddress(
                    kind: .phoneJID,
                    value: "34622222222@s.whatsapp.net"
                )
            ) == true
        )
    }

    func testOwnerContactAndProfilePhotoAreExcludedFromPortableGroup() throws {
        let fixture = try ConversationFixture()
        defer { fixture.remove() }
        let owner = MessageAuthor(
            kind: .me,
            displayName: "Private Owner",
            phone: "34611111111",
            jid: "34611111111@s.whatsapp.net",
            source: .owner
        )
        let participant = participantAuthor("34622222222", name: "Visible Member")
        let source = try fixture.source(
            id: "private-owner-contact",
            chatID: 30,
            jid: "family@g.us",
            messages: [
                .text(
                    id: 1,
                    chatID: 30,
                    offset: 1,
                    text: "Owner message",
                    isFromMe: true,
                    author: owner
                ),
                .text(
                    id: 2,
                    chatID: 30,
                    offset: 2,
                    text: "Member message",
                    isFromMe: false,
                    author: participant
                )
            ],
            media: [
                "owner.jpg": Data("private owner photo".utf8),
                "member.jpg": Data("participant photo".utf8)
            ],
            contacts: [
                ContactInfo(
                    name: "Private Owner",
                    phone: "34611111111",
                    photoFilename: "owner.jpg"
                ),
                ContactInfo(
                    name: "Visible Member",
                    phone: "34622222222",
                    photoFilename: "member.jpg"
                )
            ]
        )
        let archiveURL = fixture.root.appendingPathComponent("private-owner.fmcchat")
        let codec = PortableConversationArchiveCodec()

        let info = try codec.createArchive(
            from: source,
            producer: producer,
            destinationURL: archiveURL
        )
        let extracted = try codec.extractValidatedArchive(
            at: archiveURL,
            to: fixture.root.appendingPathComponent("private-owner")
        )
        let json = try String(contentsOf: extracted.documentURL, encoding: .utf8)
        let mediaNames = try FileManager.default.contentsOfDirectory(
            atPath: extracted.mediaDirectoryURL.path
        )

        XCTAssertFalse(json.contains("Private Owner"))
        XCTAssertFalse(json.contains("34611111111"))
        XCTAssertFalse(mediaNames.contains(where: { $0.hasSuffix("-owner.jpg") }))
        XCTAssertEqual(extracted.document.contacts.map(\.displayName), ["Visible Member"])
        XCTAssertEqual(info.manifest.media.count, 1)
        XCTAssertTrue(mediaNames.first?.hasSuffix("-member.jpg") == true)
    }

    func testIdenticalMediaIsStoredOnceAndReferencedByBothMessages() throws {
        let fixture = try ConversationFixture()
        defer { fixture.remove() }
        let data = Data("same media bytes".utf8)
        let source = try fixture.source(
            id: "media",
            chatID: 1,
            messages: [
                .media(id: 1, chatID: 1, offset: 1, filename: "first.bin"),
                .media(id: 2, chatID: 1, offset: 2, filename: "second.bin")
            ],
            media: ["first.bin": data, "second.bin": data]
        )
        let archiveURL = fixture.root.appendingPathComponent("media.fmcchat")
        let directoryURL = fixture.root.appendingPathComponent("media")
        let codec = PortableConversationArchiveCodec()

        let info = try codec.createArchive(
            from: source,
            producer: producer,
            destinationURL: archiveURL
        )
        let directory = try codec.extractValidatedArchive(
            at: archiveURL,
            to: directoryURL
        )

        XCTAssertEqual(info.manifest.media.count, 1)
        XCTAssertEqual(
            directory.document.messages[0].mediaPath,
            directory.document.messages[1].mediaPath
        )
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(
                atPath: directory.mediaDirectoryURL.path
            ).count,
            1
        )
    }

    func testEqualTimestampMessagesUseStableCanonicalOrder() throws {
        let fixture = try ConversationFixture()
        defer { fixture.remove() }
        let high = ArchiveMessageID(
            rawValue: UUID(uuidString: "ffffffff-ffff-4fff-8fff-ffffffffffff")!
        )
        let low = ArchiveMessageID(
            rawValue: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
        )
        let source = try fixture.source(
            id: "same-date",
            chatID: 1,
            messages: [
                .text(id: 1, chatID: 1, offset: 1, text: "High"),
                .text(id: 2, chatID: 1, offset: 1, text: "Low")
            ],
            stableMessageIDs: [1: high, 2: low]
        )
        let archiveURL = fixture.root.appendingPathComponent("same-date.fmcchat")
        let codec = PortableConversationArchiveCodec()

        _ = try codec.createArchive(
            from: source,
            producer: producer,
            destinationURL: archiveURL
        )
        let extracted = try codec.extractValidatedArchive(
            at: archiveURL,
            to: fixture.root.appendingPathComponent("same-date")
        )

        XCTAssertEqual(extracted.document.messages.map(\.id), [low, high])
        XCTAssertEqual(extracted.document.messages.map(\.text), ["Low", "High"])
    }

    func testInspectionRejectsTraversalAndExtraRootEntriesBeforeExtraction() throws {
        let fixture = try ConversationFixture()
        defer { fixture.remove() }
        let codec = PortableConversationArchiveCodec()
        for (name, path) in [
            ("traversal.fmcchat", "../escape"),
            ("extra.fmcchat", "unexpected.txt")
        ] {
            let archiveURL = fixture.root.appendingPathComponent(name)
            try makeArchive(at: archiveURL, entries: [(path, Data("x".utf8))])
            XCTAssertThrowsError(try codec.inspectArchive(at: archiveURL)) { error in
                guard case PortableConversationArchiveError.unsafePath = error else {
                    return XCTFail("Unexpected error: \(error)")
                }
            }
        }
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: fixture.root.deletingLastPathComponent()
                    .appendingPathComponent("escape").path
            )
        )
    }

    func testDirectoryTamperingAndUndeclaredFilesAreRejected() throws {
        let fixture = try ConversationFixture()
        defer { fixture.remove() }
        let source = try fixture.source(
            id: "tamper",
            chatID: 1,
            messages: [.text(id: 1, chatID: 1, offset: 1, text: "Original")]
        )
        let archiveURL = fixture.root.appendingPathComponent("tamper.fmcchat")
        let directoryURL = fixture.root.appendingPathComponent("tamper")
        let codec = PortableConversationArchiveCodec()
        _ = try codec.createArchive(
            from: source,
            producer: producer,
            destinationURL: archiveURL
        )
        let directory = try codec.extractValidatedArchive(
            at: archiveURL,
            to: directoryURL
        )

        try Data("tampered".utf8).append(to: directory.documentURL)
        XCTAssertThrowsError(try codec.openValidatedDirectory(at: directoryURL))

        try Data("extra".utf8).write(
            to: directory.mediaDirectoryURL.appendingPathComponent("extra.bin")
        )
        XCTAssertThrowsError(try codec.openValidatedDirectory(at: directoryURL))
    }

    func testConfiguredLimitsAndCancellationLeaveNoPartialOutput() throws {
        let fixture = try ConversationFixture()
        defer { fixture.remove() }
        let source = try fixture.source(
            id: "cancel",
            chatID: 1,
            messages: [.text(id: 1, chatID: 1, offset: 1, text: "One")]
        )
        let archiveURL = fixture.root.appendingPathComponent("cancelled.fmcchat")

        XCTAssertThrowsError(
            try PortableConversationArchiveCodec().createArchive(
                from: source,
                producer: producer,
                destinationURL: archiveURL,
                cancellation: { true }
            )
        ) { error in
            guard case PortableConversationArchiveError.cancelled = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: archiveURL.path))

        var limits = PortableArchiveLimits.default
        limits.maximumJSONByteCount = 16
        XCTAssertThrowsError(
            try PortableConversationArchiveCodec(limits: limits).createArchive(
                from: source,
                producer: producer,
                destinationURL: archiveURL
            )
        ) { error in
            guard case PortableConversationArchiveError.limitExceeded = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: archiveURL.path))
    }

    func testFailedOverwritePreservesExistingArchiveBytes() throws {
        let fixture = try ConversationFixture()
        defer { fixture.remove() }
        let source = try fixture.source(
            id: "missing-media",
            chatID: 1,
            messages: [
                .media(id: 1, chatID: 1, offset: 1, filename: "missing.bin")
            ]
        )
        let archiveURL = fixture.root.appendingPathComponent("existing.fmcchat")
        let original = Data("keep this existing archive".utf8)
        try original.write(to: archiveURL)

        XCTAssertThrowsError(
            try PortableConversationArchiveCodec().createArchive(
                from: source,
                producer: producer,
                destinationURL: archiveURL,
                overwriteExisting: true
            )
        )
        XCTAssertEqual(try Data(contentsOf: archiveURL), original)
    }

    func testDuplicateSourceMessageIDsAreRejected() throws {
        let fixture = try ConversationFixture()
        defer { fixture.remove() }
        let source = try fixture.source(
            id: "duplicate-ids",
            chatID: 1,
            messages: [
                .text(id: 1, chatID: 1, offset: 1, text: "First"),
                .text(id: 1, chatID: 1, offset: 2, text: "Second")
            ]
        )

        XCTAssertThrowsError(
            try PortableConversationArchiveCodec().createArchive(
                from: source,
                producer: producer,
                destinationURL: fixture.root.appendingPathComponent("duplicate.fmcchat")
            )
        ) { error in
            guard case PortableConversationArchiveError.invalidSource = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    private func participantAuthor(
        _ phone: String,
        name: String? = nil
    ) -> MessageAuthor {
        MessageAuthor(
            kind: .participant,
            displayName: name,
            phone: phone,
            jid: "\(phone)@s.whatsapp.net",
            source: .messageJid
        )
    }

    private func makeArchive(
        at url: URL,
        entries: [(path: String, data: Data)]
    ) throws {
        let archive = try ZIPFoundation.Archive(url: url, accessMode: .create)
        for entry in entries {
            try archive.addEntry(
                with: entry.path,
                type: .file,
                uncompressedSize: Int64(entry.data.count),
                compressionMethod: .none
            ) { position, size in
                let start = Int(position)
                let end = min(start + size, entry.data.count)
                return entry.data.subdata(in: start..<end)
            }
        }
    }
}

private extension Data {
    func append(to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { handle.closeFile() }
        handle.seekToEndOfFile()
        handle.write(self)
    }
}

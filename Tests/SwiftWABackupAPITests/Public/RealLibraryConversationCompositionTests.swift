import Foundation
import XCTest
@testable import SwiftWABackupAPI

final class RealLibraryConversationCompositionTests: XCTestCase {
    func testCompositionsMatchExistingMaterializedViewsWithoutWritingLibrary() throws {
        guard let path = ProcessInfo.processInfo.environment["FMC_REAL_LIBRARY_PATH"],
              !path.isEmpty else {
            throw XCTSkip("Set FMC_REAL_LIBRARY_PATH to run the read-only real-library validation.")
        }
        let libraryURL = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
        let libraryDocumentURL = libraryURL.appendingPathComponent("library.json")
        let libraryModificationDate = try libraryDocumentURL.resourceValues(
            forKeys: [.contentModificationDateKey]
        ).contentModificationDate
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let library = try decoder.decode(
            ValidationLibrary.self,
            from: Data(contentsOf: libraryDocumentURL)
        )
        let versions = Dictionary(uniqueKeysWithValues: library.versions.map { ($0.id, $0) })
        let mergedRoot = libraryURL.appendingPathComponent("MergedChats", isDirectory: true)
        let mergedDirectories = try FileManager.default.contentsOfDirectory(
            at: mergedRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ).filter {
            (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }
        XCTAssertFalse(mergedDirectories.isEmpty, "The real library has no materialized views to validate.")

        for mergedDirectory in mergedDirectories {
            let archive = try decoder.decode(
                ValidationArchive.self,
                from: Data(contentsOf: mergedDirectory.appendingPathComponent("archive.json"))
            )
            let expected = try decoder.decode(
                ExportedChatDocument.self,
                from: Data(contentsOf: mergedDirectory.appendingPathComponent("chat.json"))
            )
            let aliases = identityHint(
                values: (archive.contactJIDAliases ?? []) + [archive.summary.contactJid]
            )
            let sources = try archive.contributions.map { contribution -> ConversationSource in
                guard let version = versions[contribution.source.versionID] else {
                    throw ValidationError.missingVersion
                }
                let exportRoot = libraryURL
                    .appendingPathComponent("Exports", isDirectory: true)
                    .appendingPathComponent(version.exportDirectoryName, isDirectory: true)
                let exported = try ChatExportStore(rootDirectory: exportRoot)
                    .openChat(chatId: contribution.source.chatID)
                return try ConversationSource(
                    id: ConversationSourceID(rawValue: contribution.id),
                    exportedChat: exported,
                    conversationIdentityHint: aliases
                )
            }
            guard let targetContribution = archive.contributions.max(by: {
                $0.exportedAt < $1.exportedAt
            }) else {
                XCTFail("A materialized view has no contributions.")
                continue
            }
            let targetID = ConversationSourceID(rawValue: targetContribution.id)
            let destination = FileManager.default.temporaryDirectory.appendingPathComponent(
                "SwiftWABackupAPI-RealLibraryValidation-\(UUID().uuidString)",
                isDirectory: true
            )
            defer { try? FileManager.default.removeItem(at: destination) }

            let result = try ConversationCompositionEngine().compose(
                sources: sources,
                targetSourceID: targetID,
                perspectiveConstraints: [.samePerspective(sourceIDs: sources.map(\.id))],
                targetChatID: archive.summary.id,
                destinationDirectory: destination
            )
            try assertEquivalent(
                actual: result.document,
                actualMediaDirectory: result.mediaDirectoryURL,
                expected: expected,
                expectedMediaDirectory: mergedDirectory.appendingPathComponent("Media")
            )
        }

        let finalLibraryModificationDate = try libraryDocumentURL.resourceValues(
            forKeys: [.contentModificationDateKey]
        ).contentModificationDate
        XCTAssertEqual(libraryModificationDate, finalLibraryModificationDate)
    }

    func testPortableArchiveRoundTripsSmallestRealExportWithoutWritingLibrary() throws {
        guard let path = ProcessInfo.processInfo.environment["FMC_REAL_LIBRARY_PATH"],
              !path.isEmpty else {
            throw XCTSkip("Set FMC_REAL_LIBRARY_PATH to run the read-only real-library validation.")
        }
        let libraryURL = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
        let libraryDocumentURL = libraryURL.appendingPathComponent("library.json")
        let libraryModificationDate = try libraryDocumentURL.resourceValues(
            forKeys: [.contentModificationDateKey]
        ).contentModificationDate
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let library = try decoder.decode(
            ValidationLibrary.self,
            from: Data(contentsOf: libraryDocumentURL)
        )
        let candidates = try library.versions.flatMap { version -> [ExportedChat] in
            let exportRoot = libraryURL
                .appendingPathComponent("Exports", isDirectory: true)
                .appendingPathComponent(version.exportDirectoryName, isDirectory: true)
            guard FileManager.default.fileExists(atPath: exportRoot.path) else { return [] }
            let store = ChatExportStore(rootDirectory: exportRoot)
            return try store.listExportedChats().map {
                try store.openChat(chatId: $0.chatId)
            }
        }
        let exported = try XCTUnwrap(
            candidates.min {
                if $0.document.chat.mediaByteCount != $1.document.chat.mediaByteCount {
                    return $0.document.chat.mediaByteCount < $1.document.chat.mediaByteCount
                }
                return $0.document.messages.count < $1.document.messages.count
            }
        )
        let source = try ConversationSource(
            id: ConversationSourceID(rawValue: "real-portable-source"),
            exportedChat: exported
        )
        let temporaryRoot = FileManager.default.temporaryDirectory.appendingPathComponent(
            "SwiftWABackupAPI-RealPortableValidation-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: temporaryRoot,
            withIntermediateDirectories: false
        )
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let archiveURL = temporaryRoot.appendingPathComponent("conversation.fmcchat")
        let extractionURL = temporaryRoot.appendingPathComponent("extracted")
        let codec = PortableConversationArchiveCodec()

        let created = try codec.createArchive(
            from: source,
            producer: PortableArchiveProducer(name: "RealLibraryValidation", version: "1"),
            destinationURL: archiveURL
        )
        let extracted = try codec.extractValidatedArchive(
            at: archiveURL,
            to: extractionURL
        )
        let imported = try extracted.makeConversationSource(
            id: ConversationSourceID(rawValue: "real-portable-import")
        )

        XCTAssertEqual(created.manifest.messageCount, exported.document.messages.count)
        XCTAssertEqual(imported.kind, .portableDocument)
        XCTAssertEqual(imported.document.chat.chatType, exported.document.chat.chatType)
        XCTAssertEqual(imported.document.chat.contactJid, exported.document.chat.contactJid)
        XCTAssertEqual(imported.document.chat.name, exported.document.chat.name)
        XCTAssertEqual(imported.document.chat.isArchived, exported.document.chat.isArchived)
        XCTAssertEqual(imported.document.messages.count, exported.document.messages.count)
        XCTAssertEqual(
            imported.document.messages.map(messageSemanticDigest).sorted(),
            exported.document.messages.map(messageSemanticDigest).sorted()
        )
        XCTAssertEqual(
            try coreReferencedMediaContentSet(
                document: imported.document,
                mediaDirectory: imported.mediaDirectoryURL
            ),
            try coreReferencedMediaContentSet(
                document: exported.document,
                mediaDirectory: exported.mediaDirectoryURL
            )
        )
        XCTAssertTrue(
            try mediaContentSet(at: imported.mediaDirectoryURL).isSubset(
                of: mediaContentSet(at: exported.mediaDirectoryURL)
            ),
            "A portable package introduced media not present in its source export."
        )
        XCTAssertEqual(
            libraryModificationDate,
            try libraryDocumentURL.resourceValues(
                forKeys: [.contentModificationDateKey]
            ).contentModificationDate
        )
    }
}

private extension RealLibraryConversationCompositionTests {
    enum ValidationError: Error {
        case missingVersion
    }

    struct ValidationLibrary: Decodable {
        let versions: [ValidationVersion]
    }

    struct ValidationVersion: Decodable {
        let id: String
        let exportDirectoryName: String
    }

    struct ValidationArchive: Decodable {
        let contributions: [ValidationContribution]
        let summary: ChatInfo
        let contactJIDAliases: [String]?
    }

    struct ValidationContribution: Decodable {
        struct Source: Decodable {
            let versionID: String
            let chatID: Int
        }

        let id: String
        let exportedAt: Date
        let source: Source
    }

    func identityHint(values: [String]) -> CanonicalParticipantIdentity? {
        let addresses = values.compactMap { value -> ParticipantAddress? in
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if normalized.hasSuffix("@s.whatsapp.net") {
                return ParticipantAddress(kind: .phoneJID, value: normalized)
            }
            if normalized.hasSuffix("@lid") {
                return ParticipantAddress(kind: .lidJID, value: normalized)
            }
            if !normalized.contains("@"), normalized.contains(where: \.isNumber) {
                return ParticipantAddress(kind: .phone, value: normalized)
            }
            return nil
        }
        let identity = CanonicalParticipantIdentity(addresses: addresses)
        return identity.addresses.isEmpty ? nil : identity
    }

    func assertEquivalent(
        actual: ExportedChatDocument,
        actualMediaDirectory: URL,
        expected: ExportedChatDocument,
        expectedMediaDirectory: URL
    ) throws {
        XCTAssertEqual(actual.schemaVersion, expected.schemaVersion)
        XCTAssertEqual(actual.chat.id, expected.chat.id)
        XCTAssertTrue(actual.chat.contactJid == expected.chat.contactJid, "Target contact JID differs.")
        XCTAssertTrue(actual.chat.name == expected.chat.name, "Target display name differs.")
        XCTAssertEqual(actual.chat.numberMessages, expected.chat.numberMessages)
        XCTAssertEqual(actual.chat.lastMessageDate, expected.chat.lastMessageDate)
        XCTAssertEqual(actual.chat.chatType, expected.chat.chatType)
        XCTAssertEqual(actual.chat.isArchived, expected.chat.isArchived)
        XCTAssertEqual(actual.chat.mediaByteCount, expected.chat.mediaByteCount)
        XCTAssertTrue(
            digest(actual.chat.photoFilename) == digest(expected.chat.photoFilename),
            "Target chat-photo filename differs."
        )
        XCTAssertEqual(actual.messages.count, expected.messages.count)
        XCTAssertEqual(actual.contacts.count, expected.contacts.count)
        XCTAssertEqual(
            try actual.messages.map(encodedDigest),
            try expected.messages.map(encodedDigest),
            "The materialized message sequence differs."
        )
        XCTAssertEqual(
            try actual.contacts.map(encodedDigest),
            try expected.contacts.map(encodedDigest),
            "The selected contact sequence differs."
        )
        XCTAssertEqual(
            try mediaContentSet(at: actualMediaDirectory),
            try mediaContentSet(at: expectedMediaDirectory),
            "The materialized media content differs."
        )
    }

    func encodedDigest<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return ConversationSHA256.hashHex(try encoder.encode(value))
    }

    func digest(_ value: String?) -> String {
        ConversationSHA256.hashHex(Data((value ?? "<nil>").utf8))
    }

    func mediaContentSet(at directory: URL) throws -> Set<String> {
        let files = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )
        return try Set(files.compactMap { file -> String? in
            let values = try file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true else { return nil }
            return "\(try sha256File(file, cancellation: nil)):\(values.fileSize ?? 0)"
        })
    }

    func coreReferencedMediaContentSet(
        document: ExportedChatDocument,
        mediaDirectory: URL
    ) throws -> Set<String> {
        let filenames = Set(
            [document.chat.photoFilename].compactMap { $0 }
                + document.messages.compactMap(\.mediaFilename)
        )
        return try Set(filenames.map { filename in
            let file = mediaDirectory.appendingPathComponent(filename)
            let values = try file.resourceValues(forKeys: [.fileSizeKey])
            return "\(try sha256File(file, cancellation: nil)):\(values.fileSize ?? 0)"
        })
    }

    func messageSemanticDigest(_ message: MessageInfo) -> String {
        let components: [String] = [
            String(message.date.timeIntervalSince1970),
            message.isFromMe ? "me" : "other",
            message.messageType,
            message.message ?? "<nil>",
            message.caption ?? "<nil>",
            message.replyToPreview ?? "<nil>",
            message.error ?? "<nil>",
            message.seconds.map { String($0) } ?? "<nil>",
            message.latitude.map { String($0) } ?? "<nil>",
            message.longitude.map { String($0) } ?? "<nil>"
        ]
        return components.joined(separator: "\u{1F}")
    }
}

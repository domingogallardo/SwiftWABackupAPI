import Foundation
import XCTest
import GRDB
@testable import SwiftWABackupAPI

final class IPhoneBackupDiscoveryTests: XCTestCase {
    func testIPhoneBackupDiscoveryFindsGeneratedBackup() throws {
        let fixture = try PublicTestSupport.makeSampleBackup()
        defer { try? PublicTestSupport.removeItemIfExists(at: fixture.rootURL) }

        let manager = IPhoneBackupManager(iPhoneBackupsPath: fixture.rootURL.path)
        let backups = try manager.getIPhoneBackups()

        XCTAssertEqual(backups.count, 1, "Expected exactly one generated ready iPhone backup")
        XCTAssertEqual(backups[0].identifier, fixture.backup.identifier)
        XCTAssertEqual(
            URL(fileURLWithPath: backups[0].path).standardizedFileURL.path,
            URL(fileURLWithPath: fixture.backup.path).standardizedFileURL.path
        )
        XCTAssertEqual(backups[0].isEncrypted, false)
    }

    func testInspectIPhoneBackupsReturnsReadyBackupDiagnostics() throws {
        let fixture = try PublicTestSupport.makeSampleBackup()
        defer { try? PublicTestSupport.removeItemIfExists(at: fixture.rootURL) }

        let manager = IPhoneBackupManager(iPhoneBackupsPath: fixture.rootURL.path)
        let infos = try manager.inspectIPhoneBackups()
        let info = try XCTUnwrap(infos.first)

        XCTAssertEqual(info.status, .ready)
        XCTAssertTrue(info.isReady)
        XCTAssertEqual(info.isEncrypted, false)
        XCTAssertNil(info.issue)
        XCTAssertEqual(info.iPhoneBackup?.identifier, fixture.backup.identifier)
        XCTAssertEqual(info.iPhoneBackup?.isEncrypted, false)
    }

    func testInspectIPhoneBackupsReturnsEncryptedBackupDiagnostics() throws {
        let fixture = try PublicTestSupport.makeTemporaryBackup(name: "encrypted-backup", isEncrypted: true) { _ in }
        defer { try? PublicTestSupport.removeItemIfExists(at: fixture.rootURL) }

        let manager = IPhoneBackupManager(iPhoneBackupsPath: fixture.rootURL.path)
        let infos = try manager.inspectIPhoneBackups()
        let info = try XCTUnwrap(infos.first)

        XCTAssertEqual(info.status, .encrypted)
        XCTAssertFalse(info.isReady)
        XCTAssertEqual(info.isEncrypted, true)
        XCTAssertEqual(info.issue, "iPhone backup is encrypted.")
        XCTAssertEqual(info.iPhoneBackup?.isEncrypted, true)
    }

    func testInspectIPhoneBackupsReportsUnknownEncryptionStateWhenManifestPlistIsMissing() throws {
        let fixture = try PublicTestSupport.makeTemporaryBackup(name: "unknown-encryption-backup", isEncrypted: nil) { _ in }
        defer { try? PublicTestSupport.removeItemIfExists(at: fixture.rootURL) }

        let manager = IPhoneBackupManager(iPhoneBackupsPath: fixture.rootURL.path)
        let infos = try manager.inspectIPhoneBackups()
        let info = try XCTUnwrap(infos.first)

        XCTAssertEqual(info.status, .encryptionStatusUnavailable)
        XCTAssertFalse(info.isReady)
        XCTAssertNil(info.isEncrypted)
        XCTAssertEqual(
            info.issue,
            "Manifest.plist is missing, so encryption status could not be determined."
        )
        XCTAssertNil(info.iPhoneBackup?.isEncrypted)
    }

    func testOpensExtractedWhatsAppBackup() throws {
        let fixture = try PublicTestSupport.makeSampleBackup()
        defer { try? PublicTestSupport.removeItemIfExists(at: fixture.rootURL) }
        let extractedBackup = try PublicTestSupport.extractWhatsAppBackup(from: fixture)

        XCTAssertNoThrow(try WhatsAppBackupReader(backup: extractedBackup))
        XCTAssertNoThrow(try extractedBackup.openReader())
    }
}

final class ChatSmokeTests: XCTestCase {
    func testGetChatsReturnsExpectedCounts() throws {
        let (reader, fixture) = try PublicTestSupport.makeConnectedSampleBackup()
        defer { try? PublicTestSupport.removeItemIfExists(at: fixture.rootURL) }

        let chats = try reader.getChats()

        XCTAssertEqual(chats.count, 2, "Expected the generated sample backup to expose two chats")
        XCTAssertEqual(chats.filter { !$0.isArchived }.count, 2)
        XCTAssertEqual(chats.filter(\.isArchived).count, 0)
        XCTAssertEqual(chats.map(\.id), [44, 593])
        XCTAssertEqual(Set(chats.map(\.name)), ["Alias Atlas", "Business Contact"])
        XCTAssertEqual(chats.first?.numberMessages, 3)
    }

    func testGetChatReturnsOnlySupportedPublicMessages() throws {
        let (reader, fixture) = try PublicTestSupport.makeConnectedSampleBackup()
        defer { try? PublicTestSupport.removeItemIfExists(at: fixture.rootURL) }

        let chatDump = try reader.getChat(chatId: 593, directoryToSaveMedia: nil)

        XCTAssertEqual(chatDump.messages.map(\.id), [200002])
        XCTAssertEqual(chatDump.chatInfo.numberMessages, 1)
    }

    func testGetChatReturnsChatDumpPayload() throws {
        let (reader, fixture) = try PublicTestSupport.makeConnectedSampleBackup()
        defer { try? PublicTestSupport.removeItemIfExists(at: fixture.rootURL) }

        let payload: ChatDumpPayload = try reader.getChat(chatId: 44)

        XCTAssertEqual(payload.chatInfo.id, 44)
        XCTAssertEqual(payload.chatInfo.name, "Alias Atlas")
        XCTAssertEqual(payload.messages.count, 3)
        XCTAssertEqual(payload.contacts.count, 2)
    }

    func testKnownReplyIsResolved() throws {
        let (reader, fixture) = try PublicTestSupport.makeConnectedSampleBackup()
        defer { try? PublicTestSupport.removeItemIfExists(at: fixture.rootURL) }

        let chatDump = try reader.getChat(chatId: 44, directoryToSaveMedia: nil)
        let knownReply = try XCTUnwrap(chatDump.messages.first(where: { $0.id == 125482 }))

        XCTAssertEqual(knownReply.replyTo, 125479)
        XCTAssertEqual(knownReply.author?.phone, "08185296386")
    }

    func testMessagesExposeStructuredAuthor() throws {
        let (reader, fixture) = try PublicTestSupport.makeConnectedSampleBackup()
        defer { try? PublicTestSupport.removeItemIfExists(at: fixture.rootURL) }

        let chatDump = try reader.getChat(chatId: 44, directoryToSaveMedia: nil)
        let incoming = try XCTUnwrap(chatDump.messages.first(where: { $0.id == 125482 }))
        let outgoing = try XCTUnwrap(chatDump.messages.first(where: { $0.id == 125479 }))

        XCTAssertEqual(incoming.author?.kind, .participant)
        XCTAssertEqual(incoming.author?.displayName, "Alias Atlas")
        XCTAssertEqual(incoming.author?.phone, "08185296386")
        XCTAssertEqual(incoming.author?.jid, "08185296386@s.whatsapp.net")
        XCTAssertEqual(incoming.author?.source, .chatSession)

        XCTAssertEqual(outgoing.author?.kind, .me)
        XCTAssertEqual(outgoing.author?.displayName, "Me")
        XCTAssertEqual(outgoing.author?.phone, "08185296380")
        XCTAssertEqual(outgoing.author?.jid, "08185296380@s.whatsapp.net")
        XCTAssertEqual(outgoing.author?.source, .owner)
    }
}

final class MediaExportSmokeTests: XCTestCase {
    func testMediaExportNotifiesDelegateSetAfterConnecting() throws {
        let (reader, fixture) = try PublicTestSupport.makeConnectedSampleBackup()
        defer { try? PublicTestSupport.removeItemIfExists(at: fixture.rootURL) }

        let delegate = PublicMediaWriteDelegateSpy()
        let temporaryDirectory = try PublicTestSupport.makeTemporaryDirectory(prefix: "SwiftWABackupAPI-media-export")
        defer { try? PublicTestSupport.removeItemIfExists(at: temporaryDirectory) }

        reader.delegate = delegate
        _ = try reader.getChat(chatId: 44, directoryToSaveMedia: temporaryDirectory)

        XCTAssertFalse(delegate.fileNames.isEmpty, "Expected at least one media export callback")
        XCTAssertTrue(
            delegate.fileNames.contains("fea35851-6a2c-45a3-a784-003d25576b45.pdf"),
            "Expected the known document export to be reported by the delegate"
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: temporaryDirectory.appendingPathComponent("fea35851-6a2c-45a3-a784-003d25576b45.pdf").path
            )
        )
    }
}

final class ExtractedWhatsAppBackupTests: XCTestCase {
    func testExtractionCreatesPortablePathIndexAndReadme() throws {
        let mediaLocalPath = "Media/08185296386@s.whatsapp.net/a/b/example.jpg"
        let manifestPath = "Message/\(mediaLocalPath)"
        let fixture = try PublicTestSupport.makeTemporaryBackup(
            name: "sidecar-index-backup",
            additionalManifestEntries: [
                PublicBackupStoredFile(
                    relativePath: manifestPath,
                    fileHash: "ef1234567890examplemedia",
                    contents: Data("example-media".utf8)
                )
            ]
        ) { db in
            try db.execute(sql: """
                CREATE TABLE ZWAMEDIAITEM (
                    Z_PK INTEGER PRIMARY KEY,
                    ZMETADATA BLOB,
                    ZTITLE TEXT,
                    ZMEDIALOCALPATH TEXT,
                    ZMOVIEDURATION INTEGER,
                    ZLATITUDE DOUBLE,
                    ZLONGITUDE DOUBLE
                )
                """)
            try db.execute(
                sql: """
                    INSERT INTO ZWAMEDIAITEM
                    (Z_PK, ZMETADATA, ZTITLE, ZMEDIALOCALPATH, ZMOVIEDURATION, ZLATITUDE, ZLONGITUDE)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [42, nil, nil, mediaLocalPath, nil, nil, nil]
            )
        }
        let extractedRoot = try PublicTestSupport.makeTemporaryDirectory(prefix: "SwiftWABackupAPI-sidecar")
        defer { try? PublicTestSupport.removeItemIfExists(at: fixture.rootURL) }
        defer { try? PublicTestSupport.removeItemIfExists(at: extractedRoot) }

        _ = try fixture.backup.extractWhatsAppBackup(to: extractedRoot)

        let sidecarURL = extractedRoot.appendingPathComponent(".wa-backup", isDirectory: true)
        let indexURL = sidecarURL.appendingPathComponent("index.sqlite")
        let backupInfoURL = sidecarURL.appendingPathComponent("backup-info.json")
        let readmeURL = sidecarURL.appendingPathComponent("README.md")

        XCTAssertTrue(FileManager.default.fileExists(atPath: indexURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: backupInfoURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: readmeURL.path))

        let indexQueue = try DatabaseQueue(path: indexURL.path)
        try indexQueue.read { db in
            let schemaVersion = try String.fetchOne(
                db,
                sql: "SELECT value FROM metadata WHERE key = 'schema_version'"
            )
            XCTAssertEqual(schemaVersion, "1")

            let fileRow = try XCTUnwrap(Row.fetchOne(
                db,
                sql: """
                    SELECT file_id, extracted_relative_path, entry_type, exists_on_disk, byte_count
                    FROM files
                    WHERE manifest_relative_path = ?
                    """,
                arguments: [manifestPath]
            ))
            XCTAssertEqual(fileRow["file_id"], "ef1234567890examplemedia")
            XCTAssertEqual(fileRow["extracted_relative_path"], manifestPath)
            XCTAssertEqual(fileRow["entry_type"], "file")
            XCTAssertEqual(fileRow["exists_on_disk"], 1)
            XCTAssertEqual(fileRow["byte_count"], Int64("example-media".utf8.count))

            let aliasPath = try String.fetchOne(
                db,
                sql: """
                    SELECT extracted_relative_path
                    FROM path_aliases
                    WHERE normalized_alias_path = ?
                      AND reason = ?
                    """,
                arguments: [mediaLocalPath, "message-media-local-path"]
            )
            XCTAssertEqual(aliasPath, manifestPath)

            let mediaItemRow = try XCTUnwrap(Row.fetchOne(
                db,
                sql: """
                    SELECT local_path, resolved_relative_path, resolution_status
                    FROM media_items
                    WHERE media_item_id = 42
                    """
            ))
            XCTAssertEqual(mediaItemRow["local_path"], mediaLocalPath)
            XCTAssertEqual(mediaItemRow["resolved_relative_path"], manifestPath)
            XCTAssertEqual(mediaItemRow["resolution_status"], "resolved")
        }

        let backupInfo = try ExtractedWhatsAppBackup(url: extractedRoot).getBackupInfo()
        XCTAssertEqual(backupInfo.schemaVersion, 1)
        XCTAssertEqual(backupInfo.generator, "SwiftWABackupAPI")
        XCTAssertEqual(backupInfo.source.iPhoneBackupIdentifier, fixture.backup.identifier)
        XCTAssertEqual(backupInfo.source.iPhoneBackupCreationDate, fixture.backup.creationDate)
        XCTAssertEqual(backupInfo.source.isEncrypted, false)
        XCTAssertEqual(backupInfo.source.domain, whatsAppBackupDomain)
        XCTAssertEqual(backupInfo.manifestCounts.totalEntries, 2)
        XCTAssertEqual(backupInfo.manifestCounts.files, 2)
        XCTAssertEqual(backupInfo.manifestCounts.directories, 0)
        XCTAssertEqual(backupInfo.manifestCounts.otherEntries, 0)
        XCTAssertEqual(backupInfo.copyCounts.copiedFiles, 2)
        XCTAssertEqual(backupInfo.copyCounts.missingFiles, 0)
        XCTAssertEqual(backupInfo.mediaItemCounts.total, 1)
        XCTAssertEqual(backupInfo.mediaItemCounts.resolved, 1)
        XCTAssertEqual(backupInfo.mediaItemCounts.missing, 0)
        XCTAssertEqual(backupInfo.databaseCounts.mediaItems, 1)
        XCTAssertNil(backupInfo.databaseCounts.chats)
        XCTAssertNil(backupInfo.databaseCounts.messages)
        XCTAssertGreaterThan(backupInfo.sizes.extractedBytes, Int64("example-media".utf8.count))
        XCTAssertGreaterThan(backupInfo.sizes.indexBytes ?? 0, 0)
        XCTAssertTrue(backupInfo.warnings.isEmpty)

        let readme = try String(contentsOf: readmeURL, encoding: .utf8)
        XCTAssertTrue(readme.contains("Path Resolution Index"))
        XCTAssertTrue(readme.contains("backup-info.json"))
        XCTAssertTrue(readme.contains("Message/Media"))
    }

    func testExtractedBackupCanBeUsedAfterDeletingOriginalIPhoneBackup() throws {
        let fixture = try PublicTestSupport.makeSampleBackup()
        let extractedRoot = try PublicTestSupport.makeTemporaryDirectory(prefix: "SwiftWABackupAPI-extracted")
        let mediaOutput = try PublicTestSupport.makeTemporaryDirectory(prefix: "SwiftWABackupAPI-extracted-media")
        defer { try? PublicTestSupport.removeItemIfExists(at: fixture.rootURL) }
        defer { try? PublicTestSupport.removeItemIfExists(at: extractedRoot) }
        defer { try? PublicTestSupport.removeItemIfExists(at: mediaOutput) }

        let extractedDirectory = extractedRoot.appendingPathComponent("WhatsApp", isDirectory: true)
        let extractedBackup = try fixture.backup.extractWhatsAppBackup(to: extractedDirectory)

        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: extractedDirectory.appendingPathComponent("ChatStorage.sqlite").path
            )
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: extractedDirectory
                    .appendingPathComponent("Media/Document/fea35851-6a2c-45a3-a784-003d25576b45.pdf")
                    .path
            )
        )

        try PublicTestSupport.removeItemIfExists(at: fixture.rootURL)

        let reader = try extractedBackup.openReader()
        let dump = try reader.getChat(chatId: 44, directoryToSaveMedia: mediaOutput)

        XCTAssertEqual(dump.messages.count, 3)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: mediaOutput.appendingPathComponent("fea35851-6a2c-45a3-a784-003d25576b45.pdf").path
            )
        )
    }

    func testExtractionCreatesManifestDirectories() throws {
        let fixture = try PublicTestSupport.makeSampleBackup()
        defer { try? PublicTestSupport.removeItemIfExists(at: fixture.rootURL) }

        try PublicTestSupport.addMissingManifestEntry(
            to: fixture,
            relativePath: "AppState",
            fileHash: "0ddcaff156ac0f2fccea18f2d987d98e82d8878a",
            flags: 2
        )

        let extractedRoot = try PublicTestSupport.makeTemporaryDirectory(prefix: "SwiftWABackupAPI-directory-extracted")
        defer { try? PublicTestSupport.removeItemIfExists(at: extractedRoot) }

        XCTAssertNoThrow(try fixture.backup.extractWhatsAppBackup(to: extractedRoot))

        var isDirectory: ObjCBool = false
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: extractedRoot.appendingPathComponent("AppState").path,
                isDirectory: &isDirectory
            )
        )
        XCTAssertTrue(isDirectory.boolValue)
    }

    func testExtractedBackupResolvesMessageMediaPrefix() throws {
        let root = try PublicTestSupport.makeTemporaryDirectory(prefix: "SwiftWABackupAPI-message-media-prefix")
        defer { try? PublicTestSupport.removeItemIfExists(at: root) }

        let mediaURL = root.appendingPathComponent(
            "Message/Media/example@s.whatsapp.net/a/b/example.jpg"
        )
        try FileManager.default.createDirectory(
            at: mediaURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("media".utf8).write(to: mediaURL)

        let backup = ExtractedWhatsAppBackup(url: root)
        let resolvedURL = try backup.fileURL(endingWith: "Media/example@s.whatsapp.net/a/b/example.jpg")

        XCTAssertEqual(resolvedURL.standardizedFileURL.path, mediaURL.standardizedFileURL.path)
    }

    func testExtractedBackupResolvesLeadingSlashMessageMediaPrefix() throws {
        let root = try PublicTestSupport.makeTemporaryDirectory(prefix: "SwiftWABackupAPI-message-media-slash-prefix")
        defer { try? PublicTestSupport.removeItemIfExists(at: root) }

        let mediaURL = root.appendingPathComponent(
            "Message/Media/example@s.whatsapp.net/a/b/example.jpg"
        )
        try FileManager.default.createDirectory(
            at: mediaURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("media".utf8).write(to: mediaURL)

        let backup = ExtractedWhatsAppBackup(url: root)
        let resolvedURL = try backup.fileURL(endingWith: "/Media/example@s.whatsapp.net/a/b/example.jpg")

        XCTAssertEqual(resolvedURL.standardizedFileURL.path, mediaURL.standardizedFileURL.path)
    }

    func testExtractedBackupDoesNotScanForSuffixMatches() throws {
        let root = try PublicTestSupport.makeTemporaryDirectory(prefix: "SwiftWABackupAPI-no-suffix-scan")
        defer { try? PublicTestSupport.removeItemIfExists(at: root) }

        let unrelatedURL = root.appendingPathComponent(
            "Other/Media/example@s.whatsapp.net/a/b/example.jpg"
        )
        try FileManager.default.createDirectory(
            at: unrelatedURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("media".utf8).write(to: unrelatedURL)

        let backup = ExtractedWhatsAppBackup(url: root)

        XCTAssertThrowsError(
            try backup.fileURL(endingWith: "Media/example@s.whatsapp.net/a/b/example.jpg")
        ) { error in
            guard case DomainError.mediaNotFound = error else {
                return XCTFail("Expected DomainError.mediaNotFound, got \(error)")
            }
        }
    }

    func testExtractedBackupProfileLookupUsesProfileDirectoryOnly() throws {
        let root = try PublicTestSupport.makeTemporaryDirectory(prefix: "SwiftWABackupAPI-profile-lookup")
        defer { try? PublicTestSupport.removeItemIfExists(at: root) }

        let profileURL = root.appendingPathComponent("Media/Profile/12345-1.thumb")
        let unrelatedURL = root.appendingPathComponent("Message/Media/Profile/12345-999.thumb")
        try FileManager.default.createDirectory(
            at: profileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: unrelatedURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("profile".utf8).write(to: profileURL)
        try Data("message-media".utf8).write(to: unrelatedURL)

        let backup = ExtractedWhatsAppBackup(url: root)
        let files = try backup.fileDetails(containing: "Media/Profile/12345")

        XCTAssertEqual(files.map(\.filename), ["Media/Profile/12345-1.thumb"])
    }
}

import Foundation
import XCTest
@testable import SwiftWABackupAPI

final class IPhoneBackupDiscoveryTests: XCTestCase {
    func testIPhoneBackupDiscoveryFindsGeneratedBackup() throws {
        let fixture = try PublicTestSupport.makeSampleBackup()
        defer { try? PublicTestSupport.removeItemIfExists(at: fixture.rootURL) }

        let waBackup = WABackup(iPhoneBackupsPath: fixture.rootURL.path)
        let backups = try waBackup.getIPhoneBackups()

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

        let waBackup = WABackup(iPhoneBackupsPath: fixture.rootURL.path)
        let infos = try waBackup.inspectIPhoneBackups()
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

        let waBackup = WABackup(iPhoneBackupsPath: fixture.rootURL.path)
        let infos = try waBackup.inspectIPhoneBackups()
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

        let waBackup = WABackup(iPhoneBackupsPath: fixture.rootURL.path)
        let infos = try waBackup.inspectIPhoneBackups()
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

        XCTAssertNoThrow(try WABackup(whatsAppBackupAt: extractedBackup.url))
    }
}

final class ChatSmokeTests: XCTestCase {
    func testGetChatsReturnsExpectedCounts() throws {
        let (waBackup, fixture) = try PublicTestSupport.makeConnectedSampleBackup()
        defer { try? PublicTestSupport.removeItemIfExists(at: fixture.rootURL) }

        let chats = try waBackup.getChats()

        XCTAssertEqual(chats.count, 2, "Expected the generated sample backup to expose two chats")
        XCTAssertEqual(chats.filter { !$0.isArchived }.count, 2)
        XCTAssertEqual(chats.filter(\.isArchived).count, 0)
        XCTAssertEqual(chats.map(\.id), [44, 593])
        XCTAssertEqual(Set(chats.map(\.name)), ["Alias Atlas", "Business Contact"])
        XCTAssertEqual(chats.first?.numberMessages, 3)
    }

    func testGetChatReturnsOnlySupportedPublicMessages() throws {
        let (waBackup, fixture) = try PublicTestSupport.makeConnectedSampleBackup()
        defer { try? PublicTestSupport.removeItemIfExists(at: fixture.rootURL) }

        let chatDump = try waBackup.getChat(chatId: 593, directoryToSaveMedia: nil)

        XCTAssertEqual(chatDump.messages.map(\.id), [200002])
        XCTAssertEqual(chatDump.chatInfo.numberMessages, 1)
    }

    func testGetChatReturnsChatDumpPayload() throws {
        let (waBackup, fixture) = try PublicTestSupport.makeConnectedSampleBackup()
        defer { try? PublicTestSupport.removeItemIfExists(at: fixture.rootURL) }

        let payload: ChatDumpPayload = try waBackup.getChat(chatId: 44, directoryToSaveMedia: nil)

        XCTAssertEqual(payload.chatInfo.id, 44)
        XCTAssertEqual(payload.chatInfo.name, "Alias Atlas")
        XCTAssertEqual(payload.messages.count, 3)
        XCTAssertEqual(payload.contacts.count, 2)
    }

    func testKnownReplyIsResolved() throws {
        let (waBackup, fixture) = try PublicTestSupport.makeConnectedSampleBackup()
        defer { try? PublicTestSupport.removeItemIfExists(at: fixture.rootURL) }

        let chatDump = try waBackup.getChat(chatId: 44, directoryToSaveMedia: nil)
        let knownReply = try XCTUnwrap(chatDump.messages.first(where: { $0.id == 125482 }))

        XCTAssertEqual(knownReply.replyTo, 125479)
        XCTAssertEqual(knownReply.author?.phone, "08185296386")
    }

    func testMessagesExposeStructuredAuthor() throws {
        let (waBackup, fixture) = try PublicTestSupport.makeConnectedSampleBackup()
        defer { try? PublicTestSupport.removeItemIfExists(at: fixture.rootURL) }

        let chatDump = try waBackup.getChat(chatId: 44, directoryToSaveMedia: nil)
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
        let (waBackup, fixture) = try PublicTestSupport.makeConnectedSampleBackup()
        defer { try? PublicTestSupport.removeItemIfExists(at: fixture.rootURL) }

        let delegate = PublicMediaWriteDelegateSpy()
        let temporaryDirectory = try PublicTestSupport.makeTemporaryDirectory(prefix: "SwiftWABackupAPI-media-export")
        defer { try? PublicTestSupport.removeItemIfExists(at: temporaryDirectory) }

        waBackup.delegate = delegate
        _ = try waBackup.getChat(chatId: 44, directoryToSaveMedia: temporaryDirectory)

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

        let waBackup = try WABackup(whatsAppBackupAt: extractedBackup.url)
        let dump = try waBackup.getChat(chatId: 44, directoryToSaveMedia: mediaOutput)

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
}

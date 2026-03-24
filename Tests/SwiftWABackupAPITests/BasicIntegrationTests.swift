import Foundation
import XCTest
@testable import SwiftWABackupAPI

final class BackupDiscoveryTests: XCTestCase {
    func testBackupDiscoveryFindsGeneratedBackup() throws {
        let fixture = try TestSupport.makeSampleBackup()
        defer { try? TestSupport.removeItemIfExists(at: fixture.rootURL) }

        let waBackup = WABackup(backupPath: fixture.rootURL.path)
        let backups = try waBackup.getBackups()

        XCTAssertEqual(backups.validBackups.count, 1, "Expected exactly one generated valid backup")
        XCTAssertTrue(backups.invalidBackups.isEmpty)
        XCTAssertEqual(backups.validBackups[0].identifier, fixture.backup.identifier)
        XCTAssertEqual(
            URL(fileURLWithPath: backups.validBackups[0].path).standardizedFileURL.path,
            URL(fileURLWithPath: fixture.backup.path).standardizedFileURL.path
        )
    }

    func testConnectChatStorageDatabase() throws {
        let fixture = try TestSupport.makeSampleBackup()
        defer { try? TestSupport.removeItemIfExists(at: fixture.rootURL) }

        let waBackup = WABackup(backupPath: fixture.rootURL.path)

        XCTAssertNoThrow(try waBackup.connectChatStorageDb(from: fixture.backup))
    }
}

final class ChatSmokeTests: XCTestCase {
    func testGetChatsReturnsExpectedCounts() throws {
        let (waBackup, fixture) = try TestSupport.makeConnectedSampleBackup()
        defer { try? TestSupport.removeItemIfExists(at: fixture.rootURL) }

        let chats = try waBackup.getChats()

        XCTAssertEqual(chats.count, 2, "Expected the generated sample backup to expose two chats")
        XCTAssertEqual(chats.filter { !$0.isArchived }.count, 2)
        XCTAssertEqual(chats.filter(\.isArchived).count, 0)
        XCTAssertEqual(chats.map(\.id), [44, 593])
        XCTAssertEqual(Set(chats.map(\.name)), ["Aitor Medrano", "Business Contact"])
        XCTAssertEqual(chats.first?.numberMessages, 3)
    }

    func testBusinessChatStatusMessageIsNormalized() throws {
        let (waBackup, fixture) = try TestSupport.makeConnectedSampleBackup()
        defer { try? TestSupport.removeItemIfExists(at: fixture.rootURL) }

        let chatDump = try waBackup.getChat(chatId: 593, directoryToSaveMedia: nil)

        XCTAssertTrue(
            chatDump.messages.contains(where: { $0.message == "This is a business chat" }),
            "Expected at least one normalized business-chat status message"
        )
    }

    func testGetChatPayloadWrapsLegacyChatDump() throws {
        let (waBackup, fixture) = try TestSupport.makeConnectedSampleBackup()
        defer { try? TestSupport.removeItemIfExists(at: fixture.rootURL) }

        let legacyDump = try waBackup.getChat(chatId: 44, directoryToSaveMedia: nil)
        let payload = try waBackup.getChatPayload(chatId: 44, directoryToSaveMedia: nil)

        XCTAssertEqual(payload.chatInfo.id, legacyDump.chatInfo.id)
        XCTAssertEqual(payload.chatInfo.name, legacyDump.chatInfo.name)
        XCTAssertEqual(payload.messages.count, legacyDump.messages.count)
        XCTAssertEqual(payload.contacts.count, legacyDump.contacts.count)
    }

    func testKnownReplyIsResolved() throws {
        let (waBackup, fixture) = try TestSupport.makeConnectedSampleBackup()
        defer { try? TestSupport.removeItemIfExists(at: fixture.rootURL) }

        let chatDump = try waBackup.getChat(chatId: 44, directoryToSaveMedia: nil)
        let knownReply = try XCTUnwrap(chatDump.messages.first(where: { $0.id == 125482 }))

        XCTAssertEqual(knownReply.replyTo, 125479)
        XCTAssertEqual(knownReply.senderPhone, "34636104084")
    }
}

final class MediaExportSmokeTests: XCTestCase {
    func testMediaExportNotifiesDelegateSetAfterConnecting() throws {
        let (waBackup, fixture) = try TestSupport.makeConnectedSampleBackup()
        defer { try? TestSupport.removeItemIfExists(at: fixture.rootURL) }

        let delegate = MediaWriteDelegateSpy()
        let temporaryDirectory = try TestSupport.makeTemporaryDirectory(prefix: "SwiftWABackupAPI-media-export")
        defer { try? TestSupport.removeItemIfExists(at: temporaryDirectory) }

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

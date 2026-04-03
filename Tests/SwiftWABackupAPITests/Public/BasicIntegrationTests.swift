import Foundation
import XCTest
@testable import SwiftWABackupAPI

final class BackupDiscoveryTests: XCTestCase {
    func testBackupDiscoveryFindsGeneratedBackup() throws {
        let fixture = try PublicTestSupport.makeSampleBackup()
        defer { try? PublicTestSupport.removeItemIfExists(at: fixture.rootURL) }

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
        let fixture = try PublicTestSupport.makeSampleBackup()
        defer { try? PublicTestSupport.removeItemIfExists(at: fixture.rootURL) }

        let waBackup = WABackup(backupPath: fixture.rootURL.path)

        XCTAssertNoThrow(try waBackup.connectChatStorageDb(from: fixture.backup))
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

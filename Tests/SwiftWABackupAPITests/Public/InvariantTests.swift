import Foundation
import XCTest
@testable import SwiftWABackupAPI
import GRDB

final class SampleBackupInvariantTests: XCTestCase {
    func testListedChatMetadataMatchesChatExportHeader() throws {
        let (waBackup, fixture) = try PublicTestSupport.makeConnectedSampleBackup()
        defer { try? PublicTestSupport.removeItemIfExists(at: fixture.rootURL) }

        let chats = try waBackup.getChats()

        for chat in chats {
            let dump = try waBackup.getChat(chatId: chat.id, directoryToSaveMedia: nil)

            XCTAssertEqual(dump.chatInfo.id, chat.id)
            XCTAssertEqual(dump.chatInfo.contactJid, chat.contactJid)
            XCTAssertEqual(dump.chatInfo.name, chat.name)
            XCTAssertEqual(dump.chatInfo.numberMessages, chat.numberMessages)
            XCTAssertEqual(dump.chatInfo.lastMessageDate, chat.lastMessageDate)
            XCTAssertEqual(dump.chatInfo.chatType, chat.chatType)
            XCTAssertEqual(dump.chatInfo.isArchived, chat.isArchived)
        }
    }

    func testChatsAreSortedByDescendingLastMessageDate() throws {
        let (waBackup, fixture) = try PublicTestSupport.makeConnectedSampleBackup()
        defer { try? PublicTestSupport.removeItemIfExists(at: fixture.rootURL) }

        let chats = try waBackup.getChats()
        let sortedIds = chats.sorted { $0.lastMessageDate > $1.lastMessageDate }.map(\.id)

        XCTAssertEqual(chats.map(\.id), sortedIds)
    }

    func testChatExportMessagesStayWithinRequestedChat() throws {
        let (waBackup, fixture) = try PublicTestSupport.makeConnectedSampleBackup()
        defer { try? PublicTestSupport.removeItemIfExists(at: fixture.rootURL) }

        let chats = try waBackup.getChats()

        for chat in chats {
            let dump = try waBackup.getChat(chatId: chat.id, directoryToSaveMedia: nil)

            XCTAssertEqual(dump.chatInfo.id, chat.id)
            XCTAssertEqual(dump.chatInfo.numberMessages, dump.messages.count)
            XCTAssertTrue(
                dump.messages.allSatisfy { $0.chatId == chat.id },
                "Every message returned by getChat must belong to the requested chat"
            )
        }
    }

    func testReplyTargetsAlwaysExistWithinSameChat() throws {
        let (waBackup, fixture) = try PublicTestSupport.makeConnectedSampleBackup()
        defer { try? PublicTestSupport.removeItemIfExists(at: fixture.rootURL) }

        let chats = try waBackup.getChats()

        for chat in chats {
            let dump = try waBackup.getChat(chatId: chat.id, directoryToSaveMedia: nil)
            let messageIds = Set(dump.messages.map(\.id))

            for message in dump.messages {
                if let replyTarget = message.replyTo {
                    XCTAssertTrue(
                        messageIds.contains(replyTarget),
                        "Message \(message.id) replies to \(replyTarget), which is missing from chat \(chat.id)"
                    )
                }
            }
        }
    }

    func testIndividualIncomingMessagesResolveChatPartnerIdentity() throws {
        let (waBackup, fixture) = try PublicTestSupport.makeConnectedSampleBackup()
        defer { try? PublicTestSupport.removeItemIfExists(at: fixture.rootURL) }

        let chats = try waBackup.getChats()

        for chat in chats where chat.chatType == .individual {
            let dump = try waBackup.getChat(chatId: chat.id, directoryToSaveMedia: nil)
            let expectedPhone = chat.contactJid.extractedPhone

            for message in dump.messages {
                if message.isFromMe {
                    XCTAssertEqual(message.author?.kind, .me)
                    XCTAssertEqual(message.author?.displayName, "Me")
                    XCTAssertEqual(message.author?.source, .owner)
                } else {
                    XCTAssertEqual(message.author?.kind, .participant)
                    XCTAssertEqual(message.author?.displayName, chat.name)
                    XCTAssertEqual(message.author?.phone, expectedPhone)
                    XCTAssertEqual(message.author?.jid, chat.contactJid)
                    XCTAssertEqual(message.author?.source, .chatSession)
                }
            }
        }
    }

    func testContactListsContainOwnerExactlyOnceAndUseUniquePhones() throws {
        let (waBackup, fixture) = try PublicTestSupport.makeConnectedSampleBackup()
        defer { try? PublicTestSupport.removeItemIfExists(at: fixture.rootURL) }

        let chats = try waBackup.getChats()

        for chat in chats {
            let dump = try waBackup.getChat(chatId: chat.id, directoryToSaveMedia: nil)
            let phones = dump.contacts.map(\.phone)
            let meContacts = dump.contacts.filter { $0.name == "Me" }

            XCTAssertEqual(meContacts.count, 1, "Each contact list should contain exactly one owner contact")
            XCTAssertEqual(Set(phones).count, phones.count, "Contact lists should be unique by phone")

            guard let ownerPhone = meContacts.first?.phone else {
                XCTFail("Owner contact should have a phone number")
                continue
            }

            XCTAssertFalse(ownerPhone.isEmpty, "Owner phone should not be empty")

            let otherPhone = chat.contactJid.extractedPhone
            if otherPhone != ownerPhone {
                XCTAssertTrue(
                    dump.contacts.contains(where: { $0.phone == otherPhone }),
                    "Individual chats should include the remote participant in the contact list"
                )
            }
        }
    }

    func testReportedMediaFilesExistAfterExport() throws {
        let (waBackup, fixture) = try PublicTestSupport.makeConnectedSampleBackup()
        defer { try? PublicTestSupport.removeItemIfExists(at: fixture.rootURL) }

        let exportDirectory = try PublicTestSupport.makeTemporaryDirectory(prefix: "SwiftWABackupAPI-media-invariants")
        defer { try? PublicTestSupport.removeItemIfExists(at: exportDirectory) }

        let dump = try waBackup.getChat(chatId: 44, directoryToSaveMedia: exportDirectory)

        let reportedFiles = dump.messages.compactMap(\.mediaFilename)
        XCTAssertFalse(reportedFiles.isEmpty, "Expected at least one exported media file")

        for fileName in reportedFiles {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: exportDirectory.appendingPathComponent(fileName).path),
                "Reported media file \(fileName) should exist on disk after export"
            )
        }
    }

}

final class ChatDiscoveryInvariantTests: XCTestCase {
    func testGetChatsExcludesUnsupportedSessionTypes() throws {
        let (waBackup, fixture) = try InvariantFixtureFactory.makeConnectedFilteredChatBackup()
        defer { try? PublicTestSupport.removeItemIfExists(at: fixture.rootURL) }

        let chats = try waBackup.getChats()

        XCTAssertEqual(chats.map(\.id), [800])
        XCTAssertEqual(chats.first?.name, "Visible Chat")
        XCTAssertEqual(chats.first?.chatType, .individual)
    }

    func testProfilePhotoExportWritesReportedFile() throws {
        let (waBackup, fixture) = try InvariantFixtureFactory.makeConnectedProfilePhotoBackup()
        defer { try? PublicTestSupport.removeItemIfExists(at: fixture.rootURL) }

        let exportDirectory = try PublicTestSupport.makeTemporaryDirectory(prefix: "SwiftWABackupAPI-photo-invariants")
        defer { try? PublicTestSupport.removeItemIfExists(at: exportDirectory) }

        let chats = try waBackup.getChats(directoryToSavePhotos: exportDirectory)
        let chat = try XCTUnwrap(chats.first(where: { $0.id == 810 }))
        let photoFilename = try XCTUnwrap(chat.photoFilename)
        let exportedURL = exportDirectory.appendingPathComponent(photoFilename)

        XCTAssertEqual(photoFilename, "chat_810.jpg")
        XCTAssertTrue(FileManager.default.fileExists(atPath: exportedURL.path))
    }

    func testIndividualLidChatsResolvePartnerPhoneThroughLidAccount() throws {
        let (waBackup, fixture) = try InvariantFixtureFactory.makeConnectedIndividualLidBackup()
        defer { try? PublicTestSupport.removeItemIfExists(at: fixture.rootURL) }

        let chat = try XCTUnwrap(try waBackup.getChats().first(where: { $0.id == 820 }))
        let dump = try waBackup.getChat(chatId: chat.id, directoryToSaveMedia: nil)
        let incomingMessage = try XCTUnwrap(dump.messages.first(where: { !$0.isFromMe }))

        XCTAssertEqual(chat.contactJid, "40482648260486@lid")
        XCTAssertEqual(incomingMessage.author?.displayName, "Alias Birch")
        XCTAssertEqual(incomingMessage.author?.phone, "08185296385")
        XCTAssertEqual(incomingMessage.author?.jid, "08185296385@s.whatsapp.net")
        XCTAssertEqual(incomingMessage.author?.source, .chatSession)
    }

    func testLocationMessagesKeepNilCoordinatesWhenMediaItemLacksThem() throws {
        let (waBackup, fixture) = try InvariantFixtureFactory.makeConnectedIncompleteLocationBackup()
        defer { try? PublicTestSupport.removeItemIfExists(at: fixture.rootURL) }

        let chat = try XCTUnwrap(try waBackup.getChats().first(where: { $0.id == 830 }))
        let dump = try waBackup.getChat(chatId: chat.id, directoryToSaveMedia: nil)
        let message = try XCTUnwrap(dump.messages.first(where: { $0.id == 830001 }))

        XCTAssertEqual(message.messageType, "Location")
        XCTAssertNil(message.latitude)
        XCTAssertNil(message.longitude)
    }
}

final class GroupChatInvariantTests: XCTestCase {
    func testGroupIncomingMessagesResolveMemberIdentity() throws {
        let (waBackup, fixture) = try InvariantFixtureFactory.makeConnectedGroupBackup()
        defer { try? PublicTestSupport.removeItemIfExists(at: fixture.rootURL) }

        let chat = try XCTUnwrap(try waBackup.getChats().first(where: { $0.id == 700 }))
        let dump = try waBackup.getChat(chatId: chat.id, directoryToSaveMedia: nil)

        let messageById = Dictionary(uniqueKeysWithValues: dump.messages.map { ($0.id, $0) })

        let aliceMessage = try XCTUnwrap(messageById[700001])
        XCTAssertEqual(aliceMessage.author?.kind, .participant)
        XCTAssertEqual(aliceMessage.author?.displayName, "Alice Member")
        XCTAssertEqual(aliceMessage.author?.phone, "08185296378")
        XCTAssertEqual(aliceMessage.author?.jid, "08185296378@s.whatsapp.net")
        XCTAssertEqual(aliceMessage.author?.source, .groupMember)

        let bobMessage = try XCTUnwrap(messageById[700002])
        XCTAssertEqual(bobMessage.author?.kind, .participant)
        XCTAssertEqual(bobMessage.author?.displayName, "~Bob Push")
        XCTAssertEqual(bobMessage.author?.phone, "08185296379")
        XCTAssertEqual(bobMessage.author?.jid, "08185296379@s.whatsapp.net")
        XCTAssertEqual(bobMessage.author?.source, .pushName)

        let carolMessage = try XCTUnwrap(messageById[700006])
        XCTAssertEqual(carolMessage.author?.kind, .participant)
        XCTAssertEqual(carolMessage.author?.displayName, "Carol Contact")
        XCTAssertEqual(carolMessage.author?.phone, "08185296370")
        XCTAssertEqual(carolMessage.author?.jid, "08185296370@s.whatsapp.net")
        XCTAssertEqual(carolMessage.author?.source, .chatSession)

        let lidMessage = try XCTUnwrap(messageById[700007])
        XCTAssertEqual(lidMessage.author?.kind, .participant)
        XCTAssertEqual(lidMessage.author?.displayName, "Alias Cedar")
        XCTAssertEqual(lidMessage.author?.phone, "08185296389")
        XCTAssertEqual(lidMessage.author?.jid, "08185296389@s.whatsapp.net")
        XCTAssertEqual(lidMessage.author?.source, .addressBook)

        let linkedPushNameMessage = try XCTUnwrap(messageById[700008])
        XCTAssertEqual(linkedPushNameMessage.author?.kind, .participant)
        XCTAssertEqual(linkedPushNameMessage.author?.displayName, "~Delta")
        XCTAssertEqual(linkedPushNameMessage.author?.phone, "08185296371")
        XCTAssertEqual(linkedPushNameMessage.author?.jid, "08185296371@s.whatsapp.net")
        XCTAssertEqual(linkedPushNameMessage.author?.source, .pushNamePhoneJid)

        let unresolvedLidMessage = try XCTUnwrap(messageById[700009])
        XCTAssertEqual(unresolvedLidMessage.author?.kind, .participant)
        XCTAssertEqual(unresolvedLidMessage.author?.displayName, "~Alias Birch")
        XCTAssertEqual(unresolvedLidMessage.author?.phone, "08185296385")
        XCTAssertEqual(unresolvedLidMessage.author?.jid, "08185296385@s.whatsapp.net")
        XCTAssertEqual(unresolvedLidMessage.author?.source, .lidAccount)

        let stillUnresolvedLidMessage = try XCTUnwrap(messageById[700010])
        XCTAssertEqual(stillUnresolvedLidMessage.author?.kind, .participant)
        XCTAssertEqual(stillUnresolvedLidMessage.author?.displayName, "~Mystery Lid")
        XCTAssertNil(stillUnresolvedLidMessage.author?.phone)
        XCTAssertEqual(stillUnresolvedLidMessage.author?.jid, "404826482600@lid")
        XCTAssertEqual(stillUnresolvedLidMessage.author?.source, .pushName)

        let phoneOnlyChatSessionMessage = try XCTUnwrap(messageById[700011])
        XCTAssertEqual(phoneOnlyChatSessionMessage.author?.kind, .participant)
        XCTAssertEqual(phoneOnlyChatSessionMessage.author?.displayName, "~Dana Push")
        XCTAssertEqual(phoneOnlyChatSessionMessage.author?.phone, "08185296372")
        XCTAssertEqual(phoneOnlyChatSessionMessage.author?.jid, "08185296372@s.whatsapp.net")
        XCTAssertEqual(phoneOnlyChatSessionMessage.author?.source, .pushName)

        let outgoingMessage = try XCTUnwrap(messageById[700003])
        XCTAssertEqual(outgoingMessage.author?.kind, .me)
        XCTAssertEqual(outgoingMessage.author?.displayName, "Me")
        XCTAssertEqual(outgoingMessage.author?.phone, "08185296380")
        XCTAssertEqual(outgoingMessage.author?.jid, "08185296380@s.whatsapp.net")
        XCTAssertEqual(outgoingMessage.author?.source, .owner)

        XCTAssertNil(messageById[700004])
        XCTAssertNil(messageById[700005])
    }

    func testGroupContactListContainsOwnerAndDistinctMembers() throws {
        let (waBackup, fixture) = try InvariantFixtureFactory.makeConnectedGroupBackup()
        defer { try? PublicTestSupport.removeItemIfExists(at: fixture.rootURL) }

        let dump = try waBackup.getChat(chatId: 700, directoryToSaveMedia: nil)
        let phones = dump.contacts.map(\.phone)

        XCTAssertEqual(Set(phones).count, dump.contacts.count)
        XCTAssertEqual(
            Set(phones),
            Set(["08185296380", "08185296378", "08185296379", "08185296370", "08185296371", "08185296372", "08185296385", "08185296389"])
        )
        XCTAssertEqual(dump.contacts.filter { $0.name == "Me" }.count, 1)
    }
}

private enum InvariantFixtureFactory {
    static func makeConnectedFilteredChatBackup() throws -> (waBackup: WABackup, fixture: PublicTemporaryBackupFixture) {
        let fixture = try PublicTestSupport.makeTemporaryBackup(name: "filtered-chat-backup") { db in
            try createCommonTables(in: db)

            let latest = makeReferenceTimestamp(year: 2024, month: 4, day: 9, hour: 12, minute: 0, second: 0)

            try db.execute(
                sql: """
                    INSERT INTO ZWACHATSESSION
                    (Z_PK, ZCONTACTJID, ZPARTNERNAME, ZLASTMESSAGEDATE, ZMESSAGECOUNTER, ZSESSIONTYPE, ZARCHIVED)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [800, "08185296377@s.whatsapp.net", "Visible Chat", latest, 1, 0, 0]
            )
            try db.execute(
                sql: """
                    INSERT INTO ZWACHATSESSION
                    (Z_PK, ZCONTACTJID, ZPARTNERNAME, ZLASTMESSAGEDATE, ZMESSAGECOUNTER, ZSESSIONTYPE, ZARCHIVED)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [801, "newsletter-1@newsletter.whatsapp.net", "Filtered Channel", latest, 1, 5, 0]
            )

            try db.execute(
                sql: """
                    INSERT INTO ZWAMESSAGE
                    (Z_PK, ZTOJID, ZMESSAGETYPE, ZGROUPMEMBER, ZCHATSESSION, ZTEXT, ZMESSAGEDATE, ZFROMJID, ZMEDIAITEM, ZISFROMME, ZGROUPEVENTTYPE, ZSTANZAID)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    800001,
                    "08185296380@s.whatsapp.net",
                    6,
                    nil,
                    800,
                    nil,
                    latest,
                    nil,
                    nil,
                    1,
                    nil,
                    "owner-visible-1"
                ]
            )
            try db.execute(
                sql: """
                    INSERT INTO ZWAMESSAGE
                    (Z_PK, ZTOJID, ZMESSAGETYPE, ZGROUPMEMBER, ZCHATSESSION, ZTEXT, ZMESSAGEDATE, ZFROMJID, ZMEDIAITEM, ZISFROMME, ZGROUPEVENTTYPE, ZSTANZAID)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    800002,
                    "08185296380@s.whatsapp.net",
                    0,
                    nil,
                    800,
                    "Visible text message",
                    latest,
                    "08185296377@s.whatsapp.net",
                    nil,
                    0,
                    nil,
                    "visible-text-1"
                ]
            )
        }

        let waBackup = WABackup(backupPath: fixture.rootURL.path)
        try waBackup.connectChatStorageDb(from: fixture.backup)
        return (waBackup, fixture)
    }

    static func makeConnectedProfilePhotoBackup() throws -> (waBackup: WABackup, fixture: PublicTemporaryBackupFixture) {
        let fixture = try PublicTestSupport.makeTemporaryBackup(
            name: "profile-photo-backup",
            additionalManifestEntries: [
                PublicBackupStoredFile(
                    relativePath: "Media/Profile/08185296384-1712664000.jpg",
                    fileHash: "ef1234567890profilephoto",
                    contents: Data("Fake JPEG contents".utf8)
                )
            ]
        ) { db in
            try createCommonTables(in: db)

            let latest = makeReferenceTimestamp(year: 2024, month: 4, day: 9, hour: 12, minute: 0, second: 0)

            try db.execute(
                sql: """
                    INSERT INTO ZWACHATSESSION
                    (Z_PK, ZCONTACTJID, ZPARTNERNAME, ZLASTMESSAGEDATE, ZMESSAGECOUNTER, ZSESSIONTYPE, ZARCHIVED)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [810, "08185296384@s.whatsapp.net", "Photo Contact", latest, 1, 0, 0]
            )
            try db.execute(
                sql: """
                    INSERT INTO ZWACHATSESSION
                    (Z_PK, ZCONTACTJID, ZPARTNERNAME, ZLASTMESSAGEDATE, ZMESSAGECOUNTER, ZSESSIONTYPE, ZARCHIVED)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [811, "08185296380@s.whatsapp.net", "Me", latest, 1, 0, 0]
            )

            try db.execute(
                sql: """
                    INSERT INTO ZWAMESSAGE
                    (Z_PK, ZTOJID, ZMESSAGETYPE, ZGROUPMEMBER, ZCHATSESSION, ZTEXT, ZMESSAGEDATE, ZFROMJID, ZMEDIAITEM, ZISFROMME, ZGROUPEVENTTYPE, ZSTANZAID)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    811001,
                    "08185296380@s.whatsapp.net",
                    6,
                    nil,
                    811,
                    nil,
                    latest,
                    nil,
                    nil,
                    1,
                    nil,
                    "owner-photo-1"
                ]
            )
            try db.execute(
                sql: """
                    INSERT INTO ZWAMESSAGE
                    (Z_PK, ZTOJID, ZMESSAGETYPE, ZGROUPMEMBER, ZCHATSESSION, ZTEXT, ZMESSAGEDATE, ZFROMJID, ZMEDIAITEM, ZISFROMME, ZGROUPEVENTTYPE, ZSTANZAID)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    810001,
                    "08185296380@s.whatsapp.net",
                    0,
                    nil,
                    810,
                    "Chat with exported profile photo",
                    latest,
                    "08185296384@s.whatsapp.net",
                    nil,
                    0,
                    nil,
                    "photo-text-1"
                ]
            )
        }

        let waBackup = WABackup(backupPath: fixture.rootURL.path)
        try waBackup.connectChatStorageDb(from: fixture.backup)
        return (waBackup, fixture)
    }

    static func makeConnectedIndividualLidBackup() throws -> (waBackup: WABackup, fixture: PublicTemporaryBackupFixture) {
        let fixture = try PublicTestSupport.makeTemporaryBackup(name: "individual-lid-backup") { db in
            try createCommonTables(in: db)

            let latest = makeReferenceTimestamp(year: 2024, month: 4, day: 10, hour: 18, minute: 0, second: 0)

            try db.execute(
                sql: """
                    INSERT INTO ZWACHATSESSION
                    (Z_PK, ZCONTACTJID, ZPARTNERNAME, ZLASTMESSAGEDATE, ZMESSAGECOUNTER, ZSESSIONTYPE, ZARCHIVED)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [820, "40482648260486@lid", "Alias Birch", latest, 2, 0, 0]
            )

            try db.execute(
                sql: """
                    INSERT INTO ZWAPROFILEPUSHNAME
                    (ZPUSHNAME, ZJID)
                    VALUES (?, ?)
                    """,
                arguments: ["Alias Birch", "40482648260486@lid"]
            )

            try db.execute(
                sql: """
                    INSERT INTO ZWAMESSAGE
                    (Z_PK, ZTOJID, ZMESSAGETYPE, ZGROUPMEMBER, ZCHATSESSION, ZTEXT, ZMESSAGEDATE, ZFROMJID, ZMEDIAITEM, ZISFROMME, ZGROUPEVENTTYPE, ZSTANZAID)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    820000,
                    "08185296380@s.whatsapp.net",
                    6,
                    nil,
                    820,
                    nil,
                    makeReferenceTimestamp(year: 2024, month: 4, day: 10, hour: 17, minute: 59, second: 0),
                    nil,
                    nil,
                    1,
                    nil,
                    "individual-lid-owner"
                ]
            )
            try db.execute(
                sql: """
                    INSERT INTO ZWAMESSAGE
                    (Z_PK, ZTOJID, ZMESSAGETYPE, ZGROUPMEMBER, ZCHATSESSION, ZTEXT, ZMESSAGEDATE, ZFROMJID, ZMEDIAITEM, ZISFROMME, ZGROUPEVENTTYPE, ZSTANZAID)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    820001,
                    "08185296380@s.whatsapp.net",
                    0,
                    nil,
                    820,
                    "Incoming from lid-based individual chat",
                    latest,
                    "40482648260486@lid",
                    nil,
                    0,
                    nil,
                    "individual-lid-1"
                ]
            )
            try db.execute(
                sql: """
                    INSERT INTO ZWAMESSAGE
                    (Z_PK, ZTOJID, ZMESSAGETYPE, ZGROUPMEMBER, ZCHATSESSION, ZTEXT, ZMESSAGEDATE, ZFROMJID, ZMEDIAITEM, ZISFROMME, ZGROUPEVENTTYPE, ZSTANZAID)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    820002,
                    "08185296380@s.whatsapp.net",
                    0,
                    nil,
                    820,
                    "Outgoing",
                    makeReferenceTimestamp(year: 2024, month: 4, day: 10, hour: 18, minute: 1, second: 0),
                    nil,
                    nil,
                    1,
                    nil,
                    "individual-lid-2"
                ]
            )
        }

        try PublicTestSupport.addLidDatabase(to: fixture) { db in
            try db.execute(
                sql: """
                    INSERT INTO ZWAZACCOUNT
                    (Z_PK, ZIDENTIFIER, ZPHONENUMBER, ZCREATEDAT)
                    VALUES (?, ?, ?, ?)
                    """,
                arguments: [
                    1,
                    "40482648260486@lid",
                    "08185296385",
                    makeReferenceTimestamp(year: 2025, month: 2, day: 10, hour: 12, minute: 0, second: 0)
                ]
            )
        }

        let waBackup = WABackup(backupPath: fixture.rootURL.path)
        try waBackup.connectChatStorageDb(from: fixture.backup)
        return (waBackup, fixture)
    }

    static func makeConnectedGroupBackup() throws -> (waBackup: WABackup, fixture: PublicTemporaryBackupFixture) {
        let fixture = try PublicTestSupport.makeTemporaryBackup(name: "group-invariant-backup") { db in
            try createCommonTables(in: db)

            let groupLatest = makeReferenceTimestamp(year: 2024, month: 4, day: 8, hour: 11, minute: 0, second: 0)

            try db.execute(
                sql: """
                    INSERT INTO ZWACHATSESSION
                    (Z_PK, ZCONTACTJID, ZPARTNERNAME, ZLASTMESSAGEDATE, ZMESSAGECOUNTER, ZSESSIONTYPE, ZARCHIVED)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [700, "08185296380-123456@g.us", "Invariant Group", groupLatest, 10, 0, 0]
            )
            try db.execute(
                sql: """
                    INSERT INTO ZWACHATSESSION
                    (Z_PK, ZCONTACTJID, ZPARTNERNAME, ZLASTMESSAGEDATE, ZMESSAGECOUNTER, ZSESSIONTYPE, ZARCHIVED)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [701, "08185296380@s.whatsapp.net", "Me", groupLatest, 1, 0, 0]
            )
            try db.execute(
                sql: """
                    INSERT INTO ZWACHATSESSION
                    (Z_PK, ZCONTACTJID, ZPARTNERNAME, ZLASTMESSAGEDATE, ZMESSAGECOUNTER, ZSESSIONTYPE, ZARCHIVED)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [702, "08185296370@s.whatsapp.net", "\u{200E}Carol Contact", groupLatest, 1, 0, 0]
            )
            try db.execute(
                sql: """
                    INSERT INTO ZWACHATSESSION
                    (Z_PK, ZCONTACTJID, ZPARTNERNAME, ZLASTMESSAGEDATE, ZMESSAGECOUNTER, ZSESSIONTYPE, ZARCHIVED)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [703, "08185296372@s.whatsapp.net", "+08 185 29 63 72", groupLatest, 1, 0, 0]
            )

            try db.execute(
                sql: """
                    INSERT INTO ZWAGROUPMEMBER
                    (Z_PK, ZMEMBERJID, ZCONTACTNAME)
                    VALUES (?, ?, ?)
                    """,
                arguments: [501, "08185296378@s.whatsapp.net", "\u{200E}Alice Member"]
            )
            try db.execute(
                sql: """
                    INSERT INTO ZWAGROUPMEMBER
                    (Z_PK, ZMEMBERJID, ZCONTACTNAME)
                    VALUES (?, ?, ?)
                    """,
                arguments: [502, "08185296379@s.whatsapp.net", nil]
            )
            try db.execute(
                sql: """
                    INSERT INTO ZWAPROFILEPUSHNAME
                    (ZPUSHNAME, ZJID)
                    VALUES (?, ?)
                    """,
                arguments: ["\u{200E}Bob Push", "08185296379@s.whatsapp.net"]
            )
            try db.execute(
                sql: """
                    INSERT INTO ZWAGROUPMEMBER
                    (Z_PK, ZMEMBERJID, ZCONTACTNAME)
                    VALUES (?, ?, ?)
                    """,
                arguments: [503, "08185296370@s.whatsapp.net", "Carol Group"]
            )
            try db.execute(
                sql: """
                    INSERT INTO ZWAPROFILEPUSHNAME
                    (ZPUSHNAME, ZJID)
                    VALUES (?, ?)
                    """,
                arguments: ["Carol Push", "08185296370@s.whatsapp.net"]
            )
            try db.execute(
                sql: """
                    INSERT INTO ZWAGROUPMEMBER
                    (Z_PK, ZMEMBERJID, ZCONTACTNAME)
                    VALUES (?, ?, ?)
                    """,
                arguments: [504, "40482648260485@lid", nil]
            )
            try db.execute(
                sql: """
                    INSERT INTO ZWAPROFILEPUSHNAME
                    (ZPUSHNAME, ZJID)
                    VALUES (?, ?)
                    """,
                arguments: ["Alias Cedar", "40482648260485@lid"]
            )
            try db.execute(
                sql: """
                    INSERT INTO ZWAGROUPMEMBER
                    (Z_PK, ZMEMBERJID, ZCONTACTNAME)
                    VALUES (?, ?, ?)
                    """,
                arguments: [505, "404826482604827@lid", nil]
            )
            try db.execute(
                sql: """
                    INSERT INTO ZWAGROUPMEMBER
                    (Z_PK, ZMEMBERJID, ZCONTACTNAME)
                    VALUES (?, ?, ?)
                    """,
                arguments: [506, "40482648260486@lid", nil]
            )
            try db.execute(
                sql: """
                    INSERT INTO ZWAPROFILEPUSHNAME
                    (ZPUSHNAME, ZJID)
                    VALUES (?, ?)
                    """,
                arguments: ["Delta", "404826482604827@lid"]
            )
            try db.execute(
                sql: """
                    INSERT INTO ZWAPROFILEPUSHNAME
                    (ZPUSHNAME, ZJID)
                    VALUES (?, ?)
                    """,
                arguments: ["Delta", "08185296371@s.whatsapp.net"]
            )
            try db.execute(
                sql: """
                    INSERT INTO ZWAPROFILEPUSHNAME
                    (ZPUSHNAME, ZJID)
                    VALUES (?, ?)
                    """,
                arguments: ["Alias Birch", "40482648260486@lid"]
            )
            try db.execute(
                sql: """
                    INSERT INTO ZWAGROUPMEMBER
                    (Z_PK, ZMEMBERJID, ZCONTACTNAME)
                    VALUES (?, ?, ?)
                    """,
                arguments: [507, "404826482600@lid", nil]
            )
            try db.execute(
                sql: """
                    INSERT INTO ZWAGROUPMEMBER
                    (Z_PK, ZMEMBERJID, ZCONTACTNAME)
                    VALUES (?, ?, ?)
                    """,
                arguments: [508, "08185296372@s.whatsapp.net", "\u{202A}+08 185 29 63 72\u{202C}"]
            )
            try db.execute(
                sql: """
                    INSERT INTO ZWAPROFILEPUSHNAME
                    (ZPUSHNAME, ZJID)
                    VALUES (?, ?)
                    """,
                arguments: ["Mystery Lid", "404826482600@lid"]
            )
            try db.execute(
                sql: """
                    INSERT INTO ZWAPROFILEPUSHNAME
                    (ZPUSHNAME, ZJID)
                    VALUES (?, ?)
                    """,
                arguments: ["Dana Push", "08185296372@s.whatsapp.net"]
            )

            try db.execute(
                sql: """
                    INSERT INTO ZWAMESSAGE
                    (Z_PK, ZTOJID, ZMESSAGETYPE, ZGROUPMEMBER, ZCHATSESSION, ZTEXT, ZMESSAGEDATE, ZFROMJID, ZMEDIAITEM, ZISFROMME, ZGROUPEVENTTYPE, ZSTANZAID)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    700001,
                    "08185296380-123456@g.us",
                    0,
                    501,
                    700,
                    "Hello from Alice",
                    makeReferenceTimestamp(year: 2024, month: 4, day: 8, hour: 10, minute: 0, second: 0),
                    "08185296378@s.whatsapp.net",
                    nil,
                    0,
                    nil,
                    "group-1"
                ]
            )
            try db.execute(
                sql: """
                    INSERT INTO ZWAMESSAGE
                    (Z_PK, ZTOJID, ZMESSAGETYPE, ZGROUPMEMBER, ZCHATSESSION, ZTEXT, ZMESSAGEDATE, ZFROMJID, ZMEDIAITEM, ZISFROMME, ZGROUPEVENTTYPE, ZSTANZAID)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    700002,
                    "08185296380-123456@g.us",
                    0,
                    502,
                    700,
                    "Hello from Bob",
                    makeReferenceTimestamp(year: 2024, month: 4, day: 8, hour: 10, minute: 30, second: 0),
                    "08185296379@s.whatsapp.net",
                    nil,
                    0,
                    nil,
                    "group-2"
                ]
            )
            try db.execute(
                sql: """
                    INSERT INTO ZWAMESSAGE
                    (Z_PK, ZTOJID, ZMESSAGETYPE, ZGROUPMEMBER, ZCHATSESSION, ZTEXT, ZMESSAGEDATE, ZFROMJID, ZMEDIAITEM, ZISFROMME, ZGROUPEVENTTYPE, ZSTANZAID)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    700003,
                    "08185296380-123456@g.us",
                    0,
                    nil,
                    700,
                    "Hello from me",
                    groupLatest,
                    nil,
                    nil,
                    1,
                    nil,
                    "group-3"
                ]
            )
            try db.execute(
                sql: """
                    INSERT INTO ZWAMESSAGE
                    (Z_PK, ZTOJID, ZMESSAGETYPE, ZGROUPMEMBER, ZCHATSESSION, ZTEXT, ZMESSAGEDATE, ZFROMJID, ZMEDIAITEM, ZISFROMME, ZGROUPEVENTTYPE, ZSTANZAID)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    700006,
                    "08185296380-123456@g.us",
                    0,
                    503,
                    700,
                    "Hello from Carol",
                    makeReferenceTimestamp(year: 2024, month: 4, day: 8, hour: 10, minute: 40, second: 0),
                    "08185296370@s.whatsapp.net",
                    nil,
                    0,
                    nil,
                    "group-6"
                ]
            )
            try db.execute(
                sql: """
                    INSERT INTO ZWAMESSAGE
                    (Z_PK, ZTOJID, ZMESSAGETYPE, ZGROUPMEMBER, ZCHATSESSION, ZTEXT, ZMESSAGEDATE, ZFROMJID, ZMEDIAITEM, ZISFROMME, ZGROUPEVENTTYPE, ZSTANZAID)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    700007,
                    "08185296380-123456@g.us",
                    0,
                    504,
                    700,
                    "Hello from Cedar via LID",
                    makeReferenceTimestamp(year: 2024, month: 4, day: 8, hour: 10, minute: 42, second: 0),
                    "40482648260485@lid",
                    nil,
                    0,
                    nil,
                    "group-7"
                ]
            )
            try db.execute(
                sql: """
                    INSERT INTO ZWAMESSAGE
                    (Z_PK, ZTOJID, ZMESSAGETYPE, ZGROUPMEMBER, ZCHATSESSION, ZTEXT, ZMESSAGEDATE, ZFROMJID, ZMEDIAITEM, ZISFROMME, ZGROUPEVENTTYPE, ZSTANZAID)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    700008,
                    "08185296380-123456@g.us",
                    0,
                    505,
                    700,
                    "Hello from Delta via linked push name",
                    makeReferenceTimestamp(year: 2024, month: 4, day: 8, hour: 10, minute: 43, second: 0),
                    "404826482604827@lid",
                    nil,
                    0,
                    nil,
                    "group-8"
                ]
            )
            try db.execute(
                sql: """
                    INSERT INTO ZWAMESSAGE
                    (Z_PK, ZTOJID, ZMESSAGETYPE, ZGROUPMEMBER, ZCHATSESSION, ZTEXT, ZMESSAGEDATE, ZFROMJID, ZMEDIAITEM, ZISFROMME, ZGROUPEVENTTYPE, ZSTANZAID)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    700009,
                    "08185296380-123456@g.us",
                    0,
                    506,
                    700,
                    "Hello from an unresolved LID participant",
                    makeReferenceTimestamp(year: 2024, month: 4, day: 8, hour: 10, minute: 44, second: 0),
                    "40482648260486@lid",
                    nil,
                    0,
                    nil,
                    "group-9"
                ]
            )
            try db.execute(
                sql: """
                    INSERT INTO ZWAMESSAGE
                    (Z_PK, ZTOJID, ZMESSAGETYPE, ZGROUPMEMBER, ZCHATSESSION, ZTEXT, ZMESSAGEDATE, ZFROMJID, ZMEDIAITEM, ZISFROMME, ZGROUPEVENTTYPE, ZSTANZAID)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    700010,
                    "08185296380-123456@g.us",
                    0,
                    507,
                    700,
                    "Hello from a still unresolved LID participant",
                    makeReferenceTimestamp(year: 2024, month: 4, day: 8, hour: 10, minute: 44, second: 30),
                    "404826482600@lid",
                    nil,
                    0,
                    nil,
                    "group-10"
                ]
            )
            try db.execute(
                sql: """
                    INSERT INTO ZWAMESSAGE
                    (Z_PK, ZTOJID, ZMESSAGETYPE, ZGROUPMEMBER, ZCHATSESSION, ZTEXT, ZMESSAGEDATE, ZFROMJID, ZMEDIAITEM, ZISFROMME, ZGROUPEVENTTYPE, ZSTANZAID)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    700011,
                    "08185296380-123456@g.us",
                    0,
                    508,
                    700,
                    "Phone-only direct chat labels should not outrank push names in groups",
                    makeReferenceTimestamp(year: 2024, month: 4, day: 8, hour: 10, minute: 44, second: 45),
                    "08185296372@s.whatsapp.net",
                    nil,
                    0,
                    nil,
                    "group-11"
                ]
            )
            try db.execute(
                sql: """
                    INSERT INTO ZWAMESSAGE
                    (Z_PK, ZTOJID, ZMESSAGETYPE, ZGROUPMEMBER, ZCHATSESSION, ZTEXT, ZMESSAGEDATE, ZFROMJID, ZMEDIAITEM, ZISFROMME, ZGROUPEVENTTYPE, ZSTANZAID)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    700004,
                    "08185296380-123456@g.us",
                    10,
                    501,
                    700,
                    "token",
                    makeReferenceTimestamp(year: 2024, month: 4, day: 8, hour: 10, minute: 45, second: 0),
                    "08185296378@s.whatsapp.net",
                    nil,
                    0,
                    40,
                    "group-status-1"
                ]
            )
            try db.execute(
                sql: """
                    INSERT INTO ZWAMESSAGE
                    (Z_PK, ZTOJID, ZMESSAGETYPE, ZGROUPMEMBER, ZCHATSESSION, ZTEXT, ZMESSAGEDATE, ZFROMJID, ZMEDIAITEM, ZISFROMME, ZGROUPEVENTTYPE, ZSTANZAID)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    700005,
                    "08185296380-123456@g.us",
                    10,
                    nil,
                    700,
                    nil,
                    makeReferenceTimestamp(year: 2024, month: 4, day: 8, hour: 10, minute: 50, second: 0),
                    "08185296380-123456@g.us",
                    nil,
                    0,
                    2,
                    "group-status-2"
                ]
            )
            try db.execute(
                sql: """
                    INSERT INTO ZWAMESSAGE
                    (Z_PK, ZTOJID, ZMESSAGETYPE, ZGROUPMEMBER, ZCHATSESSION, ZTEXT, ZMESSAGEDATE, ZFROMJID, ZMEDIAITEM, ZISFROMME, ZGROUPEVENTTYPE, ZSTANZAID)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    701001,
                    "08185296380@s.whatsapp.net",
                    6,
                    nil,
                    701,
                    nil,
                    makeReferenceTimestamp(year: 2024, month: 4, day: 8, hour: 9, minute: 0, second: 0),
                    nil,
                    nil,
                    1,
                    nil,
                    "owner-status-1"
                ]
            )
        }

        try PublicTestSupport.addContactsDatabase(to: fixture) { db in
            try db.execute(
                sql: """
                    INSERT INTO ZWAADDRESSBOOKCONTACT
                    (Z_PK, ZFULLNAME, ZGIVENNAME, ZBUSINESSNAME, ZLID, ZPHONENUMBER, ZWHATSAPPID)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    1,
                    "Alias Cedar",
                    "Cedar",
                    nil,
                    "40482648260485@lid",
                    "690 103 286",
                    "08185296389@s.whatsapp.net"
                ]
            )
        }

        try PublicTestSupport.addLidDatabase(to: fixture) { db in
            try db.execute(
                sql: """
                    INSERT INTO ZWAZACCOUNT
                    (Z_PK, ZIDENTIFIER, ZPHONENUMBER, ZCREATEDAT)
                    VALUES (?, ?, ?, ?)
                    """,
                arguments: [
                    1,
                    "40482648260486@lid",
                    "08185296385",
                    makeReferenceTimestamp(year: 2025, month: 2, day: 10, hour: 12, minute: 0, second: 0)
                ]
            )
        }

        let waBackup = WABackup(backupPath: fixture.rootURL.path)
        try waBackup.connectChatStorageDb(from: fixture.backup)
        return (waBackup, fixture)
    }

    static func makeConnectedIncompleteLocationBackup() throws -> (waBackup: WABackup, fixture: PublicTemporaryBackupFixture) {
        let fixture = try PublicTestSupport.makeTemporaryBackup(name: "incomplete-location-backup") { db in
            try createCommonTables(in: db)

            let latest = makeReferenceTimestamp(year: 2024, month: 4, day: 11, hour: 18, minute: 0, second: 0)

            try db.execute(
                sql: """
                    INSERT INTO ZWACHATSESSION
                    (Z_PK, ZCONTACTJID, ZPARTNERNAME, ZLASTMESSAGEDATE, ZMESSAGECOUNTER, ZSESSIONTYPE, ZARCHIVED)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [830, "08185296387@s.whatsapp.net", "Location Contact", latest, 1, 0, 0]
            )

            try db.execute(
                sql: """
                    INSERT INTO ZWAMEDIAITEM
                    (Z_PK, ZMETADATA, ZTITLE, ZMEDIALOCALPATH, ZMOVIEDURATION, ZLATITUDE, ZLONGITUDE)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [8301, nil, nil, nil, nil, nil, nil]
            )

            try db.execute(
                sql: """
                    INSERT INTO ZWAMESSAGE
                    (Z_PK, ZTOJID, ZMESSAGETYPE, ZGROUPMEMBER, ZCHATSESSION, ZTEXT, ZMESSAGEDATE, ZFROMJID, ZMEDIAITEM, ZISFROMME, ZGROUPEVENTTYPE, ZSTANZAID)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    830001,
                    "08185296380@s.whatsapp.net",
                    5,
                    nil,
                    830,
                    nil,
                    latest,
                    "08185296387@s.whatsapp.net",
                    8301,
                    0,
                    nil,
                    "location-incomplete-1"
                ]
            )
        }

        let waBackup = WABackup(backupPath: fixture.rootURL.path)
        try waBackup.connectChatStorageDb(from: fixture.backup)
        return (waBackup, fixture)
    }

    private static func createCommonTables(in db: Database) throws {
        try db.execute(sql: """
            CREATE TABLE ZWACHATSESSION (
                Z_PK INTEGER PRIMARY KEY,
                ZCONTACTJID TEXT,
                ZPARTNERNAME TEXT,
                ZLASTMESSAGEDATE DOUBLE,
                ZMESSAGECOUNTER INTEGER,
                ZSESSIONTYPE INTEGER,
                ZARCHIVED INTEGER
            )
            """)
        try db.execute(sql: """
            CREATE TABLE ZWAMESSAGE (
                Z_PK INTEGER PRIMARY KEY,
                ZTOJID TEXT,
                ZMESSAGETYPE INTEGER,
                ZGROUPMEMBER INTEGER,
                ZCHATSESSION INTEGER,
                ZTEXT TEXT,
                ZMESSAGEDATE DOUBLE,
                ZFROMJID TEXT,
                ZMEDIAITEM INTEGER,
                ZISFROMME INTEGER,
                ZGROUPEVENTTYPE INTEGER,
                ZSTANZAID TEXT,
                ZPARENTMESSAGE INTEGER
            )
            """)
        try db.execute(sql: """
            CREATE TABLE ZWAGROUPMEMBER (
                Z_PK INTEGER PRIMARY KEY,
                ZMEMBERJID TEXT,
                ZCONTACTNAME TEXT
            )
            """)
        try db.execute(sql: """
            CREATE TABLE ZWAPROFILEPUSHNAME (
                ZPUSHNAME TEXT,
                ZJID TEXT
            )
            """)
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
        try db.execute(sql: """
            CREATE TABLE ZWAMESSAGEINFO (
                Z_PK INTEGER PRIMARY KEY,
                ZRECEIPTINFO BLOB,
                ZMESSAGE INTEGER
            )
            """)
    }

    private static func makeReferenceTimestamp(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int,
        second: Int
    ) -> TimeInterval {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second

        return (components.date ?? Date(timeIntervalSinceReferenceDate: 0)).timeIntervalSinceReferenceDate
    }
}

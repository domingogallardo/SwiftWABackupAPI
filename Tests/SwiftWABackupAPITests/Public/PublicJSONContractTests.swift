import Foundation
import XCTest
@testable import SwiftWABackupAPI

final class PublicJSONContractTests: XCTestCase {
    func testReactionJSONContract() throws {
        let reaction = Reaction(
            emoji: "👍",
            author: MessageAuthor(
                kind: .participant,
                displayName: "~ Alias Ember",
                phone: "08185296388",
                jid: "404826482604828@lid",
                source: .lidAccount
            )
        )

        let json = try PublicTestSupport.canonicalJSONString(reaction)

        XCTAssertEqual(
            json,
            """
            {
              "author" : {
                "displayName" : "~ Alias Ember",
                "jid" : "404826482604828@lid",
                "kind" : "participant",
                "phone" : "08185296388",
                "source" : "lidAccount"
              },
              "emoji" : "👍"
            }
            """
        )
    }

    func testMessageAuthorJSONContract() throws {
        let author = MessageAuthor(
            kind: .participant,
            displayName: "Alias Atlas",
            phone: "08185296386",
            jid: "08185296386@s.whatsapp.net",
            source: .chatSession
        )

        let json = try PublicTestSupport.canonicalJSONString(author)

        XCTAssertEqual(
            json,
            """
            {
              "displayName" : "Alias Atlas",
              "jid" : "08185296386@s.whatsapp.net",
              "kind" : "participant",
              "phone" : "08185296386",
              "source" : "chatSession"
            }
            """
        )
    }

    func testChatInfoJSONContract() throws {
        let date = Date(timeIntervalSince1970: 1_712_143_456)
        let chatInfo = ChatInfo(
            id: 44,
            contactJid: "08185296386@s.whatsapp.net",
            name: "Alias Atlas",
            numberMessages: 153,
            lastMessageDate: date,
            isArchived: false,
            mediaByteCount: 3_221_225_472,
            photoFilename: "chat_44.jpg"
        )

        let json = try PublicTestSupport.canonicalJSONString(chatInfo)

        XCTAssertEqual(
            json,
            """
            {
              "chatType" : "individual",
              "contactJid" : "08185296386@s.whatsapp.net",
              "id" : 44,
              "isArchived" : false,
              "lastMessageDate" : "2024-04-03T11:24:16Z",
              "mediaByteCount" : 3221225472,
              "name" : "Alias Atlas",
              "numberMessages" : 153,
              "photoFilename" : "chat_44.jpg"
            }
            """
        )
    }

    func testChatInfoDecodesLegacyJSONWithoutMediaByteCount() throws {
        let data = Data(
            """
            {
              "chatType": "individual",
              "contactJid": "08185296386@s.whatsapp.net",
              "id": 44,
              "isArchived": false,
              "lastMessageDate": "2024-04-03T11:24:16Z",
              "name": "Alias Atlas",
              "numberMessages": 153
            }
            """.utf8
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let chatInfo = try decoder.decode(ChatInfo.self, from: data)

        XCTAssertEqual(chatInfo.mediaByteCount, 0)
    }

    func testIPhoneBackupDiscoveryInfoReadyJSONContract() throws {
        let date = Date(timeIntervalSince1970: 1_712_143_456)
        let info = IPhoneBackupDiscoveryInfo(
            identifier: "sample-backup",
            path: "/tmp/sample-backup",
            creationDate: date,
            isEncrypted: false,
            status: .ready,
            issue: nil
        )

        let json = try PublicTestSupport.canonicalJSONString(info)

        XCTAssertEqual(
            json,
            """
            {
              "creationDate" : "2024-04-03T11:24:16Z",
              "identifier" : "sample-backup",
              "isEncrypted" : false,
              "isReady" : true,
              "path" : "\\/tmp\\/sample-backup",
              "status" : "ready"
            }
            """
        )
    }

    func testIPhoneBackupDiscoveryInfoEncryptedJSONContract() throws {
        let date = Date(timeIntervalSince1970: 1_712_143_456)
        let info = IPhoneBackupDiscoveryInfo(
            identifier: "encrypted-backup",
            path: "/tmp/encrypted-backup",
            creationDate: date,
            isEncrypted: true,
            status: .encrypted,
            issue: "iPhone backup is encrypted."
        )

        let json = try PublicTestSupport.canonicalJSONString(info)

        XCTAssertEqual(
            json,
            """
            {
              "creationDate" : "2024-04-03T11:24:16Z",
              "identifier" : "encrypted-backup",
              "isEncrypted" : true,
              "isReady" : false,
              "issue" : "iPhone backup is encrypted.",
              "path" : "\\/tmp\\/encrypted-backup",
              "status" : "encrypted"
            }
            """
        )
    }

    func testExtractedWhatsAppBackupInfoJSONContract() throws {
        let date = Date(timeIntervalSince1970: 1_712_143_456)
        let info = ExtractedWhatsAppBackupInfo(
            schemaVersion: 1,
            generator: "SwiftWABackupAPI",
            generatedAt: date,
            source: ExtractedWhatsAppBackupInfo.Source(
                iPhoneBackupIdentifier: "sample-backup",
                iPhoneBackupCreationDate: date,
                isEncrypted: false,
                domain: "AppDomainGroup-group.net.whatsapp.WhatsApp.shared"
            ),
            manifestCounts: ExtractedWhatsAppBackupInfo.ManifestCounts(
                totalEntries: 12,
                files: 10,
                directories: 1,
                otherEntries: 1
            ),
            copyCounts: ExtractedWhatsAppBackupInfo.CopyCounts(
                copiedFiles: 9,
                missingFiles: 1
            ),
            mediaItemCounts: ExtractedWhatsAppBackupInfo.MediaItemCounts(
                total: 4,
                resolved: 3,
                missing: 1
            ),
            databaseCounts: ExtractedWhatsAppBackupInfo.DatabaseCounts(
                chats: 2,
                messages: 5,
                supportedMessages: 4,
                mediaItems: 4,
                contacts: 3,
                lidAccounts: 1,
                groupMembers: 6,
                profilePushNames: 7
            ),
            sizes: ExtractedWhatsAppBackupInfo.Sizes(
                extractedBytes: 123_456,
                indexBytes: 2_048
            ),
            warnings: [
                "Could not read ContactsV2.sqlite counts: sample warning"
            ]
        )

        let json = try PublicTestSupport.canonicalJSONString(info)

        XCTAssertEqual(
            json,
            """
            {
              "copyCounts" : {
                "copiedFiles" : 9,
                "missingFiles" : 1
              },
              "databaseCounts" : {
                "chats" : 2,
                "contacts" : 3,
                "groupMembers" : 6,
                "lidAccounts" : 1,
                "mediaItems" : 4,
                "messages" : 5,
                "profilePushNames" : 7,
                "supportedMessages" : 4
              },
              "generatedAt" : "2024-04-03T11:24:16Z",
              "generator" : "SwiftWABackupAPI",
              "manifestCounts" : {
                "directories" : 1,
                "files" : 10,
                "otherEntries" : 1,
                "totalEntries" : 12
              },
              "mediaItemCounts" : {
                "missing" : 1,
                "resolved" : 3,
                "total" : 4
              },
              "schemaVersion" : 1,
              "sizes" : {
                "extractedBytes" : 123456,
                "indexBytes" : 2048
              },
              "source" : {
                "domain" : "AppDomainGroup-group.net.whatsapp.WhatsApp.shared",
                "iPhoneBackupCreationDate" : "2024-04-03T11:24:16Z",
                "iPhoneBackupIdentifier" : "sample-backup",
                "isEncrypted" : false
              },
              "warnings" : [
                "Could not read ContactsV2.sqlite counts: sample warning"
              ]
            }
            """
        )
    }

    func testMessageInfoJSONContract() throws {
        let date = Date(timeIntervalSince1970: 1_712_143_456)
        var messageInfo = MessageInfo(
            id: 125482,
            chatId: 44,
            message: "Vale, cuando pase por la zona te escribo.",
            date: date,
            isFromMe: false,
            messageType: "Text",
            author: MessageAuthor(
                kind: .participant,
                displayName: "Alias Atlas",
                phone: "08185296386",
                jid: "08185296386@s.whatsapp.net",
                source: .chatSession
            )
        )
        messageInfo.caption = "Example caption"
        messageInfo.replyTo = 125479
        messageInfo.replyToPreview = "Original message."
        messageInfo.mediaFilename = "example.jpg"
        messageInfo.reactions = [
            Reaction(
                emoji: "👍",
                author: MessageAuthor(
                    kind: .me,
                    displayName: "Me",
                    phone: nil,
                    jid: nil,
                    source: .owner
                )
            )
        ]
        messageInfo.seconds = 12
        messageInfo.latitude = 38.3456
        messageInfo.longitude = -0.4815

        let json = try PublicTestSupport.canonicalJSONString(messageInfo)

        XCTAssertEqual(
            json,
            """
            {
              "author" : {
                "displayName" : "Alias Atlas",
                "jid" : "08185296386@s.whatsapp.net",
                "kind" : "participant",
                "phone" : "08185296386",
                "source" : "chatSession"
              },
              "caption" : "Example caption",
              "chatId" : 44,
              "date" : "2024-04-03T11:24:16Z",
              "id" : 125482,
              "isFromMe" : false,
              "latitude" : 38.3456,
              "longitude" : -0.4815,
              "mediaFilename" : "example.jpg",
              "message" : "Vale, cuando pase por la zona te escribo.",
              "messageType" : "Text",
              "reactions" : [
                {
                  "author" : {
                    "displayName" : "Me",
                    "kind" : "me",
                    "source" : "owner"
                  },
                  "emoji" : "👍"
                }
              ],
              "replyTo" : 125479,
              "replyToPreview" : "Original message.",
              "seconds" : 12
            }
            """
        )
    }

    func testContactInfoJSONContract() throws {
        let contact = ContactInfo(
            name: "Alias Atlas",
            phone: "08185296386",
            photoFilename: "08185296386.jpg"
        )

        let json = try PublicTestSupport.canonicalJSONString(contact)

        XCTAssertEqual(
            json,
            """
            {
              "name" : "Alias Atlas",
              "phone" : "08185296386",
              "photoFilename" : "08185296386.jpg"
            }
            """
        )
    }

    func testChatDumpPayloadJSONContract() throws {
        let date = Date(timeIntervalSince1970: 1_712_143_456)
        let chatInfo = ChatInfo(
            id: 44,
            contactJid: "08185296386@s.whatsapp.net",
            name: "Alias Atlas",
            numberMessages: 1,
            lastMessageDate: date,
            isArchived: false,
            photoFilename: "chat_44.jpg"
        )

        var messageInfo = MessageInfo(
            id: 125482,
            chatId: 44,
            message: "Vale, cuando pase por la zona te escribo.",
            date: date,
            isFromMe: false,
            messageType: "Text",
            author: MessageAuthor(
                kind: .participant,
                displayName: "Alias Atlas",
                phone: "08185296386",
                jid: "08185296386@s.whatsapp.net",
                source: .chatSession
            )
        )
        messageInfo.replyTo = 125479
        messageInfo.replyToPreview = "Original message."
        messageInfo.reactions = [
            Reaction(
                emoji: "👍",
                author: MessageAuthor(
                    kind: .me,
                    displayName: "Me",
                    phone: nil,
                    jid: nil,
                    source: .owner
                )
            )
        ]

        let payload = ChatDumpPayload(
            chatInfo: chatInfo,
            messages: [messageInfo],
            contacts: [
                ContactInfo(
                    name: "Alias Atlas",
                    phone: "08185296386",
                    photoFilename: "08185296386.jpg"
                )
            ]
        )

        let json = try PublicTestSupport.canonicalJSONString(payload)

        XCTAssertEqual(
            json,
            """
            {
              "chatInfo" : {
                "chatType" : "individual",
                "contactJid" : "08185296386@s.whatsapp.net",
                "id" : 44,
                "isArchived" : false,
                "lastMessageDate" : "2024-04-03T11:24:16Z",
                "mediaByteCount" : 0,
                "name" : "Alias Atlas",
                "numberMessages" : 1,
                "photoFilename" : "chat_44.jpg"
              },
              "contacts" : [
                {
                  "name" : "Alias Atlas",
                  "phone" : "08185296386",
                  "photoFilename" : "08185296386.jpg"
                }
              ],
              "messages" : [
                {
                  "author" : {
                    "displayName" : "Alias Atlas",
                    "jid" : "08185296386@s.whatsapp.net",
                    "kind" : "participant",
                    "phone" : "08185296386",
                    "source" : "chatSession"
                  },
                  "chatId" : 44,
                  "date" : "2024-04-03T11:24:16Z",
                  "id" : 125482,
                  "isFromMe" : false,
                  "message" : "Vale, cuando pase por la zona te escribo.",
                  "messageType" : "Text",
                  "reactions" : [
                    {
                      "author" : {
                        "displayName" : "Me",
                        "kind" : "me",
                        "source" : "owner"
                      },
                      "emoji" : "👍"
                    }
                  ],
                  "replyTo" : 125479,
                  "replyToPreview" : "Original message."
                }
              ]
            }
            """
        )
    }

    func testMessageInfoDecodesLegacyJSONWithoutReplyToPreview() throws {
        let data = Data(
            """
            {
              "chatId": 44,
              "date": "2024-04-03T11:24:16Z",
              "id": 125482,
              "isFromMe": false,
              "message": "Example",
              "messageType": "Text",
              "replyTo": 125479
            }
            """.utf8
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let message = try decoder.decode(MessageInfo.self, from: data)

        XCTAssertEqual(message.replyTo, 125479)
        XCTAssertNil(message.replyToPreview)
    }

    func testExportedChatDocumentRoundTripsCurrentSchema() throws {
        let date = Date(timeIntervalSince1970: 1_712_143_456)
        let chatInfo = ChatInfo(
            id: 44,
            contactJid: "08185296386@s.whatsapp.net",
            name: "Alias Atlas",
            numberMessages: 1,
            lastMessageDate: date,
            isArchived: false
        )
        let message = MessageInfo(
            id: 125482,
            chatId: 44,
            message: "Example",
            date: date,
            isFromMe: false,
            messageType: "Text"
        )
        let payload = ChatDumpPayload(
            chatInfo: chatInfo,
            messages: [message],
            contacts: [ContactInfo(name: "Alias Atlas", phone: "08185296386")]
        )
        let document = ExportedChatDocument(payload: payload, exportedAt: date)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(document)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ExportedChatDocument.self, from: data)

        XCTAssertEqual(decoded.schemaVersion, ExportedChatDocument.currentSchemaVersion)
        XCTAssertEqual(decoded.exportedAt, date)
        XCTAssertEqual(decoded.chat.id, 44)
        XCTAssertEqual(decoded.messages.first?.message, "Example")
        XCTAssertEqual(decoded.contacts.first?.phone, "08185296386")
    }

    func testExportedChatDocumentRejectsUnsupportedSchema() throws {
        let data = Data(#"{"schemaVersion":999}"#.utf8)

        XCTAssertThrowsError(try JSONDecoder().decode(ExportedChatDocument.self, from: data)) { error in
            guard case DecodingError.dataCorrupted = error else {
                return XCTFail("Expected DecodingError.dataCorrupted, got \(error)")
            }
        }
    }
}

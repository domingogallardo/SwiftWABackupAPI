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
              "name" : "Alias Atlas",
              "numberMessages" : 153,
              "photoFilename" : "chat_44.jpg"
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
                  "replyTo" : 125479
                }
              ]
            }
            """
        )
    }
}

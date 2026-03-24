import Foundation
import XCTest
@testable import SwiftWABackupAPI

final class JSONContractTests: XCTestCase {
    func testReactionJSONSnapshot() throws {
        let reaction = Reaction(emoji: "👍", senderPhone: "34636104084")
        let json = try TestSupport.canonicalJSONString(reaction)

        XCTAssertEqual(json, try TestSupport.loadFixture(named: "JSONContract/reaction.json"))
    }

    func testChatInfoJSONSnapshot() throws {
        let date = Date(timeIntervalSince1970: 1_712_143_456)
        let chatInfo = ChatInfo(
            id: 44,
            contactJid: "34636104084@s.whatsapp.net",
            name: "Aitor Medrano",
            numberMessages: 153,
            lastMessageDate: date,
            isArchived: false,
            photoFilename: "chat_44.jpg"
        )

        let json = try TestSupport.canonicalJSONString(chatInfo)
        XCTAssertEqual(json, try TestSupport.loadFixture(named: "JSONContract/chat_info.json"))
    }

    func testMessageInfoJSONSnapshot() throws {
        let date = Date(timeIntervalSince1970: 1_712_143_456)
        var messageInfo = MessageInfo(
            id: 125482,
            chatId: 44,
            message: "Claro, cada vez que vaya a la UA te aviso.",
            date: date,
            isFromMe: false,
            messageType: "Text"
        )
        messageInfo.senderName = "Aitor Medrano"
        messageInfo.senderPhone = "34636104084"
        messageInfo.caption = "Example caption"
        messageInfo.replyTo = 125479
        messageInfo.mediaFilename = "example.jpg"
        messageInfo.reactions = [Reaction(emoji: "👍", senderPhone: "Me")]
        messageInfo.seconds = 12
        messageInfo.latitude = 38.3456
        messageInfo.longitude = -0.4815

        let json = try TestSupport.canonicalJSONString(messageInfo)
        XCTAssertEqual(json, try TestSupport.loadFixture(named: "JSONContract/message_info.json"))
    }

    func testContactInfoJSONSnapshot() throws {
        let contact = ContactInfo(name: "Aitor Medrano", phone: "34636104084", photoFilename: "34636104084.jpg")
        let json = try TestSupport.canonicalJSONString(contact)

        XCTAssertEqual(json, try TestSupport.loadFixture(named: "JSONContract/contact_info.json"))
    }

    func testChatDumpPayloadJSONSnapshot() throws {
        let date = Date(timeIntervalSince1970: 1_712_143_456)
        let chatInfo = ChatInfo(
            id: 44,
            contactJid: "34636104084@s.whatsapp.net",
            name: "Aitor Medrano",
            numberMessages: 1,
            lastMessageDate: date,
            isArchived: false,
            photoFilename: "chat_44.jpg"
        )

        var messageInfo = MessageInfo(
            id: 125482,
            chatId: 44,
            message: "Claro, cada vez que vaya a la UA te aviso.",
            date: date,
            isFromMe: false,
            messageType: "Text"
        )
        messageInfo.senderName = "Aitor Medrano"
        messageInfo.senderPhone = "34636104084"
        messageInfo.replyTo = 125479
        messageInfo.reactions = [Reaction(emoji: "👍", senderPhone: "Me")]

        let payload = ChatDumpPayload(
            chatInfo: chatInfo,
            messages: [messageInfo],
            contacts: [ContactInfo(name: "Aitor Medrano", phone: "34636104084", photoFilename: "34636104084.jpg")]
        )

        let json = try TestSupport.canonicalJSONString(payload)
        XCTAssertEqual(json, try TestSupport.loadFixture(named: "JSONContract/chat_dump_payload.json"))
    }
}

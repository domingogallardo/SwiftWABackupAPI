//
//  SwiftWABackupAPI.swift
//
//
//  Created by Domingo Gallardo on 24/05/23.
//

import Foundation
import GRDB

public struct ChatInfo: CustomStringConvertible, Encodable {
    public enum ChatType: String, Codable {
        case group
        case individual
    }

    public let id: Int
    public let contactJid: String
    public let name: String
    public let numberMessages: Int
    public let lastMessageDate: Date
    public let chatType: ChatType
    
    init(id: Int, contactJid: String, name: String, numberMessages: Int, lastMessageDate: Date) {
        self.id = id
        self.contactJid = contactJid
        self.name = name
        self.numberMessages = numberMessages
        self.lastMessageDate = lastMessageDate
        self.chatType = contactJid.hasSuffix("@g.us") ? .group : .individual
    }

    public var description: String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .medium
        let localDateString = dateFormatter.string(from: lastMessageDate)

        return "Chat: ID - \(id), ContactJid - \(contactJid), " 
            + "Name - \(name), Number of Messages - \(numberMessages), "
            + "Last Message Date - \(localDateString)"
            + "Chat Type - \(chatType.rawValue)"
        }
}

public struct Reaction: Encodable {
    public let emoji: String
    public let senderPhone: String
}

/*
Type of messages supported:
  - Text (MessageType = 0)
  - Image (MessageType = 1)
  - Video (MessageType = 2)
  - Audio (MessageType = 3)
  - Location (MessageType = 5)
  - Links (MessageType = 7)
  - Docs (MessageType = 8)
  - GIFs (MessageType = 11)
  - Sticker (MessageType = 15)
*/


public struct MessageInfo: CustomStringConvertible, Encodable {
    public let id: Int
    public let chatId: Int
    public let chatGroup: Bool
    public let message: String?
    public let date: Date
    public let isFromMe: Bool 
    public let messageType: String
    public var senderName: String?
    public var senderPhone: String?
    public var caption: String?
    public var replyTo: Int?
    public var mediaFileName: String?
    public var reactions: [Reaction]?
    public var error: String?

    public var description: String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .medium
        let localDateString = dateFormatter.string(from: date)

        return "Message: ID - \(id), IsFromMe - \(isFromMe), Message - \(message ?? ""), Date - \(localDateString)"
    }
}

public protocol WABackupDelegate: AnyObject {
    func didWriteMediaFile(fileName: String)
}

public class WABackup {

    let phoneBackup = BackupManager()
    public weak var delegate: WABackupDelegate?

    // We allow to connect to more than one ChatStorage.sqlite file at the same time
    // The key is the backup identifier
    private var chatDatabases: [String: DatabaseQueue] = [:]

    public init() {}    
    
    // This function checks if any local backups exist at the default backup path.
    public func hasLocalBackups() -> Bool {
        return phoneBackup.hasLocalBackups()
    }

    
    // The function needs permission to access ~/Library/Application Support/MobileSync/Backup/
    // Go to System Preferences -> Security & Privacy -> Full Disk Access
    public func getLocalBackups() -> [IPhoneBackup] {
        return phoneBackup.getLocalBackups()
    }

    
    // Obtains the URL of the ChatStorage.sqlite file in a backup and
    // associates it with the backup identifier. The API can be connected to
    // more than one ChatStorage.sqlite file at the same time.
    public func connectChatStorageDb(from iPhoneBackup: IPhoneBackup) -> Bool {
        guard let chatStorageUrl = iPhoneBackup.getUrl(relativePath: "ChatStorage.sqlite") else {
            print("Error: No ChatStorage.sqlite file found in backup")
            return false
        }

        guard let chatStorageDb = try? DatabaseQueue(path: chatStorageUrl.path) else {
            print("Error: Cannot connect to ChatStorage.sqlite file")
            return false
        }

        // Store the connected DatabaseQueue for future use
        chatDatabases[iPhoneBackup.identifier] = chatStorageDb
        return true
    }

    public func getChats(from iPhoneBackup: IPhoneBackup) -> [ChatInfo] {
        guard let db = chatDatabases[iPhoneBackup.identifier] else {
            print("Error: ChatStorage.sqlite database is not connected for this backup")
            return []
        }
        let chats = fetchChats(from: db)
        return chats.sorted { $0.lastMessageDate > $1.lastMessageDate }
    }

    public func getChatMessages(chatId: Int, directoryToSaveMedia directory: URL, from iPhoneBackup: IPhoneBackup) -> [MessageInfo] {
        guard let db = chatDatabases[iPhoneBackup.identifier] else {
            print("Error: ChatStorage.sqlite database is not connected for this backup")
            return []
        }
        guard let chatInfo = fetchChatInfo(id: chatId, from: db) else {
            print("Error: Chat with id \(chatId) not found")
            return []
        }
        let messages = fetchChatMessages(chatId: chatId, type: chatInfo.chatType, directoryToSaveMedia: directory, 
                                        iPhoneBackup: iPhoneBackup, from: db)
        return messages.sorted { $0.date > $1.date }
    }

    // Private functions

    private func fetchChats(from db: DatabaseQueue) -> [ChatInfo] {
        var chatInfos: [ChatInfo] = []
        do {
            try db.read { db in
                // Chats ending with "status" are not real chats
                let chatSessions = try Row.fetchAll(db, sql: "SELECT * FROM ZWACHATSESSION WHERE ZCONTACTJID NOT LIKE ?", arguments: ["%@status"])
                for chatRow in chatSessions {
                    let chatId = chatRow["Z_PK"] as? Int64 ?? 0
                    let contactJid = chatRow["ZCONTACTJID"] as? String ?? "Unknown"
                    let chatName = chatRow["ZPARTNERNAME"] as? String ?? "Unknown"
                    let lastMessageDate = convertTimestampToDate(timestamp: chatRow["ZLASTMESSAGEDATE"] as Any)
                    let numberChatMessages = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM ZWAMESSAGE WHERE ZCHATSESSION = ?", arguments: [chatId]) ?? 0
                    // Chats with just one message are not real chats
                    if numberChatMessages > 1 {
                        let chatInfo = ChatInfo(id: Int(chatId), contactJid: contactJid, name: chatName, numberMessages: numberChatMessages, lastMessageDate: lastMessageDate)
                        chatInfos.append(chatInfo)
                    }
                }
            }
            return chatInfos
        } catch {
            print("Database access error: \(error)")
            return []
        }
    }

    private func fetchChatInfo(id: Int, from dbQueue: DatabaseQueue) -> ChatInfo? {
        var chatInfo: ChatInfo?
        do {
            try dbQueue.read { db in
                if let chatRow = try Row.fetchOne(db, sql: """
                    SELECT Z_PK, ZCONTACTJID, ZPARTNERNAME, ZMESSAGECOUNTER, ZLASTMESSAGEDATE
                    FROM ZWACHATSESSION
                    WHERE Z_PK = ?
                    """, arguments: [id]) {

                    let chatId = chatRow["Z_PK"] as? Int ?? 0
                    let name = chatRow["ZPARTNERNAME"] as? String ?? ""
                    let contactJid = chatRow["ZCONTACTJID"] as? String ?? ""
                    let numberMessages = chatRow["ZMESSAGECOUNTER"] as? Int ?? 0
                    let lastMessageDate = convertTimestampToDate(timestamp: chatRow["ZLASTMESSAGEDATE"] as Any)
                    
                    chatInfo = ChatInfo(id: chatId, contactJid: contactJid, name: name, 
                                        numberMessages: numberMessages, lastMessageDate: lastMessageDate)
                }
            }
            return chatInfo
        } catch {
            print("Database access error: \(error)")
            return nil
        }
    }


    private func convertTimestampToDate(timestamp: Any) -> Date {
        if let timestamp = timestamp as? Double {
            return Date(timeIntervalSinceReferenceDate: timestamp)
        } else if let timestamp = timestamp as? Int64 {
            return Date(timeIntervalSinceReferenceDate: Double(timestamp))
        }
        return Date(timeIntervalSinceReferenceDate: 0)
    }


    private func fetchChatMessages(chatId: Int, type: ChatInfo.ChatType, directoryToSaveMedia: URL, 
                                    iPhoneBackup: IPhoneBackup, from dbQueue: DatabaseQueue) -> [MessageInfo] {
        var messages: [MessageInfo] = []
        do {
            try dbQueue.read { db in
                let chatMessages = try Row.fetchAll(db, sql: """
                    SELECT ZWAMESSAGE.Z_PK, ZWAMESSAGE.ZTEXT, ZWAMESSAGE.ZMESSAGEDATE, 
                           ZWAMESSAGE.ZGROUPMEMBER, ZWAMESSAGE.ZFROMJID, ZWAMESSAGE.ZMEDIAITEM, 
                           ZWAMESSAGE.ZISFROMME, ZWAMESSAGE.ZGROUPEVENTTYPE, ZWAMESSAGE.ZMESSAGETYPE
                    FROM ZWAMESSAGE
                    WHERE ZWAMESSAGE.ZCHATSESSION = ?
                    """, arguments: [chatId])
                
                for messageRow in chatMessages {
                    let messageId = messageRow["Z_PK"] as? Int64 ?? 0
                    let messageText = messageRow["ZTEXT"] as? String
                    let messageDate = convertTimestampToDate(timestamp: messageRow["ZMESSAGEDATE"] as Any)
                    let isFromMe = messageRow["ZISFROMME"] as? Int64 == 1
                    let messageType = messageRow["ZMESSAGETYPE"] as? Int64 ?? 0

                    var messageTypeStr = ""

                    switch messageType {
                        case 0:
                            messageTypeStr = "Text"
                        case 1:
                            messageTypeStr = "Image"
                        case 2:
                            messageTypeStr = "Video"
                        case 3:
                            messageTypeStr = "Audio"
                        case 5:
                            messageTypeStr = "Location"
                        case 7:
                            messageTypeStr = "Link"
                        case 8:
                            messageTypeStr = "Document"
                        case 11:
                            messageTypeStr = "GIF"
                        case 15:
                            messageTypeStr = "Sticker"
                        default:
                            // We don't support other message types
                            // and skip this message
                            continue
                    }

                    var messageInfo = MessageInfo(id: Int(messageId), chatId: chatId, 
                                                  chatGroup: type == .group,
                                                  message: messageText, date: messageDate, isFromMe: isFromMe,
                                                  messageType: messageTypeStr)

                    if !isFromMe {

                        // obtain the sender name and phone number

                        switch type {
                            case .group:
                                let groupMemberId = messageRow["ZGROUPMEMBER"] as? Int64    
                                if let groupMemberId = groupMemberId {
                                    let (senderName, senderPhone) = try fetchSenderInfo(groupMemberId: groupMemberId, from: db)
                                    messageInfo.senderName = senderName
                                    messageInfo.senderPhone = senderPhone
                                }
                                
                            case .individual:
                                // We don't use the ZFROMJID field because there are cases where 
                                // is a broadcast message and the ZFROMJID is of the form: number@broadcast
                                let (senderName, senderPhone) = try fetchSenderInfo(fromChatSession: chatId, from: db)
                                messageInfo.senderName = senderName
                                messageInfo.senderPhone = senderPhone
                        }
                    }

                    // if it is a reply update the id of the message that is replying to

                    if let mediaItemId = messageRow["ZMEDIAITEM"] as? Int64 {
                        if let replyMessageId = 
                            try fetchReplyMessageId(mediaItemId: mediaItemId, from: db) {
                            messageInfo.replyTo = Int(replyMessageId)
                        }
                    }

                    // if it is an image, extract the image and the caption

                    if let mediaItemId = messageRow["ZMEDIAITEM"] as? Int64 {
                        if let mediaFileName = try fetchMediaFileName(forMessageId: messageInfo.id, from: iPhoneBackup, 
                                                                        toDirectory: directoryToSaveMedia, from: db) {
                            
                            switch mediaFileName {
                                case .fileName(let fileName):
                                    messageInfo.mediaFileName = fileName
                                case .error(let error):
                                    messageInfo.error = error
                            }

                            // call the delegate function after the media file is written
                            if let mediaFileName = messageInfo.mediaFileName {
                                delegate?.didWriteMediaFile(fileName: mediaFileName)
                            }

                            if let caption = try fetchCaption(mediaItemId: mediaItemId, from: db) {
                                messageInfo.caption = caption
                            }

                        }
                    }

                    // extract the reactions

                    messageInfo.reactions = try fetchReactions(forMessageId: messageInfo.id, from: db)

                    messages.append(messageInfo)
                }
            }
            return messages
        } catch {
            print("Error: \(error)")
            return []
        }
    }

    typealias SenderInfo = (senderName: String?, senderPhone: String?)


    // Returns the sender name and phone number
    // from a group member id, available in group chats
    // of a message that is not from me
    private func fetchSenderInfo(groupMemberId: Int64, from db: Database) throws -> SenderInfo {
        var senderName: String? = nil
        var senderPhone: String? = nil

        if let memberRow = try Row.fetchOne(db, sql: """
            SELECT ZMEMBERJID, ZCONTACTNAME FROM ZWAGROUPMEMBER WHERE Z_PK = ?
            """, arguments: [groupMemberId]), 
        let memberJid = memberRow["ZMEMBERJID"] as? String {

            senderPhone = extractPhone(from: memberJid)
            
            // First try to get the name from the JID
            // and if the name is not available in the JID, try to get it from the ZCONTACTNAME field
            // in the ZWAGROUPMEMBER table
            senderName = (try? fetchSenderName(for: memberJid, from: db))
                    ?? memberRow["ZCONTACTNAME"] as? String 
        }
        return (senderName, senderPhone)
    }

    // Returns the sender name and phone number from a chat id, available in individual chats
    // of a message that is not from me
    private func fetchSenderInfo(fromChatSession chatId: Int, from db: Database) throws -> SenderInfo {
        var senderName: String? = nil
        var senderPhone: String? = nil

        if let sessionRow = try Row.fetchOne(db, sql: """
            SELECT ZCONTACTJID, ZPARTNERNAME FROM ZWACHATSESSION WHERE Z_PK = ?
            """, arguments: [chatId]) {
            if let contactJid = sessionRow["ZCONTACTJID"] as? String {
                senderPhone = extractPhone(from: contactJid)
            }
            if let partnerName = sessionRow["ZPARTNERNAME"] as? String {
                senderName = partnerName
            }
        }
        return (senderName, senderPhone)
    }

    // Returns the contact name associated with a JID of the form: 34555931253@s.whatsapp.net
    private func fetchSenderName(for contactJid: String, from db: Database) throws -> String? {
        if let name: String = try Row.fetchOne(db, sql: """
            SELECT ZPARTNERNAME FROM ZWACHATSESSION WHERE ZCONTACTJID = ?
            """, arguments: [contactJid])?["ZPARTNERNAME"] {
            return name
        } else if let name: String = try Row.fetchOne(db, sql: """
            SELECT ZPUSHNAME FROM ZWAPROFILEPUSHNAME WHERE ZJID = ?
            """, arguments: [contactJid])?["ZPUSHNAME"] {
            return "~"+name
        } else {
            return nil
        }
    }

    // Returns the first part of ah JID of the form:  34555931253@s.whatsapp.net
    private func extractPhone(from jid: String?) -> String {
        return jid?.components(separatedBy: "@").first ?? ""
    }

    private func fetchReplyMessageId(mediaItemId: Int64, from db: Database) throws -> Int64? {
        let mediaItemRow = try Row.fetchOne(db, sql: """
            SELECT ZMETADATA
            FROM ZWAMEDIAITEM
            WHERE Z_PK = ?
            """, arguments: [mediaItemId])
        
        if let binaryData = mediaItemRow?["ZMETADATA"] as? Data {
            if let stanzaId = parseReplyMetadata(blob: binaryData) {
                return fetchOriginalMessageId(stanzaId: stanzaId, from: db)
            } 
        }
        return nil
    }

    // Returns the stanza id of the message that is being replied to
    private func parseReplyMetadata(blob: Data) -> String? {
        let start = blob.startIndex.advanced(by: 2)
        var end: Int? = nil
        let endMarker: [UInt8] = [0x32, 0x1A] // hexadecimal 32 1A
        let endMarkerMe: [UInt8] = [0x9A, 0x01] // hexadecimal 9A 01 if the message is sent by me

        for i in start..<blob.count - 1 {
            if blob[i] == endMarker[0] && blob[i+1] == endMarker[1] {
                end = i
                break
            } else if blob[i] == endMarkerMe[0] && blob[i+1] == endMarkerMe[1] {
                end = i
                break
            }
        }

        guard let endIndex = end else {
            // The end marker was not found in the blob
            return nil
        }

        // Start scanning backwards from the end marker
        var stanzaIDEnd = endIndex
        for i in (start..<endIndex).reversed() {
            let asciiValue = blob[i]
            // ASCII space is 32 (0x20) and characters less than this are control characters.
            if asciiValue <= 0x20 {
                break
            }
            stanzaIDEnd = i
        }

        let stanzaIDRange = stanzaIDEnd..<endIndex
        let stanzaIDData = blob.subdata(in: stanzaIDRange)
        return String(data: stanzaIDData, encoding: .utf8)
    }

    private func fetchOriginalMessageId(stanzaId: String, from db: Database) -> Int64? {
        do {
            let messageRow = try Row.fetchOne(db, sql: """
                SELECT Z_PK
                FROM ZWAMESSAGE
                WHERE ZSTANZAID = ?
                """, arguments: [stanzaId])
            return messageRow?["Z_PK"] as? Int64
        } catch {
            print("Database access error: \(error)")
            return nil
        }
    }

    private func fetchCaption(mediaItemId: Int64, from db: Database) throws -> String? {
        let mediaItemRow = try Row.fetchOne(db, sql: """
            SELECT ZTITLE
            FROM ZWAMEDIAITEM
            WHERE Z_PK = ?
            """, arguments: [mediaItemId])
        if let caption = mediaItemRow?["ZTITLE"] as? String, !caption.isEmpty {
            return caption
        }
        return nil
    }

    enum MediaFileName {
        case fileName(String)
        case error(String)
    }

    private func fetchMediaFileName(forMessageId messageId: Int, from iPhoneBackup: IPhoneBackup, 
                                    toDirectory directoryURL: URL, from db: Database) throws -> MediaFileName? {
        if let messageRow = try Row.fetchOne(db, sql: "SELECT ZMEDIAITEM FROM ZWAMESSAGE WHERE Z_PK = ?", arguments: [messageId]),
        let mediaItemId = messageRow["ZMEDIAITEM"] as? Int64,
        let mediaItemRow = try Row.fetchOne(db, sql: "SELECT ZMEDIALOCALPATH FROM ZWAMEDIAITEM WHERE Z_PK = ?", arguments: [mediaItemId]),
        let mediaLocalPath = mediaItemRow["ZMEDIALOCALPATH"] as? String {

            guard let sourceFileUrl = iPhoneBackup.getUrl(relativePath: mediaLocalPath) else {
                return MediaFileName.error("Media file not found: \(mediaLocalPath)")
            }

            let targetFileUrl = directoryURL.appendingPathComponent(URL(fileURLWithPath: mediaLocalPath).lastPathComponent)
            try FileManager.default.copyItem(at: sourceFileUrl, to: targetFileUrl)

            return MediaFileName.fileName(targetFileUrl.lastPathComponent)
        }
        return nil
    }

    private func fetchReactions(forMessageId messageId: Int, from db: Database) throws -> [Reaction]? {
        if let reactionsRow = try Row.fetchOne(db, sql: """
            SELECT ZRECEIPTINFO
            FROM ZWAMESSAGEINFO
            WHERE ZMESSAGE = ?
            """, arguments: [messageId]) {
            if let reactionsData = reactionsRow["ZRECEIPTINFO"] as? Data {
                return extractReactions(from: reactionsData)
            }
        }
        return nil
    }
    
    // Extracts the reactions of a message from a byte array by scanning for emojis
    // and extracting the phone number of the sender that is present just before the emoji.
    private func extractReactions(from data: Data) -> [Reaction]? {
        var reactions: [Reaction] = []
        let dataArray = [UInt8](data)
        var i = 0

        while i < dataArray.count {
            // Before the emoji there is a byte with the length of the emoji
            let emojiLength = Int(dataArray[i])
            if emojiLength <= 28 {
                // The maximum possible length of an emoji is 28 bytes (e.g. 👨‍👩‍👧‍👦)
                i += 1
                let emojiEndIndex = i + emojiLength
                if emojiEndIndex <= dataArray.count {
                    let emojiData = dataArray[i..<emojiEndIndex]
                    // Check if the bytes are a single emoji
                    if let emojiStr = String(bytes: emojiData, encoding: .utf8), isSingleEmoji(emojiStr) {
                        let senderPhone = extractPhoneNumber(from: dataArray, endIndex: i-2)
                        reactions.append(Reaction(emoji: emojiStr, senderPhone: senderPhone ?? "Me"))
                        i = emojiEndIndex - 1
                    }
                }
            } else {
                i += 1 
            }
        }
        return reactions.isEmpty ? nil : reactions
    }


    // Checks if a string is a single emoji.
    // The emoji can be a single character or a sequence of characters (e.g. 👨‍👩‍👧‍👦)
    private func isSingleEmoji(_ string: String) -> Bool {
        guard string.count == 1, let character = string.first else {
            // The string has more than one character or is empty
            return false
        }
        
        let scalars = character.unicodeScalars
        guard let firstScalar = scalars.first else {
            // The character has no scalars
            return false
        }

        return firstScalar.properties.isEmoji && 
            (firstScalar.properties.isEmojiPresentation || scalars.contains { $0.properties.isEmojiPresentation })
    }

    // Extracts the phone number from a byte array of the form: phone-number@s.whatsapp.net
    // The endIndex is the index of the last byte of the phone number
    private func extractPhoneNumber(from data: [UInt8], endIndex: Int) -> String? {
        let senderSuffix = "@s.whatsapp.net"
        let suffixData = Array(senderSuffix.utf8)
        var endIndex = endIndex - 1
        
        // Check if the senderSuffix is present
        var suffixEndIndex = suffixData.count - 1
        while suffixEndIndex >= 0 && endIndex >= 0 {
            if data[endIndex] != suffixData[suffixEndIndex] {
                return nil
            }
            suffixEndIndex -= 1
            endIndex -= 1
        }

        // The senderSuffix was not fully found
        if suffixEndIndex >= 0 {
            return nil
        }

        // Extract the phone number
        var phoneNumberData: [UInt8] = []
        while endIndex >= 0 {
            let char = data[endIndex]
            if char < 48 || char > 57 { // ASCII values for '0' is 48 and '9' is 57
                break
            }
            phoneNumberData.append(char)
            endIndex -= 1
        }

        // The phone number was not found
        if phoneNumberData.isEmpty {
            return nil
        }

        // Convert the phone number data to a string
        let phoneNumber = String(bytes: phoneNumberData.reversed(), encoding: .utf8)
        return phoneNumber
    }
}

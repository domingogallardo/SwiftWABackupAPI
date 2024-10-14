//
//  SwiftWABackupAPI.swift
//
//
//  Created by Domingo Gallardo on 24/05/23.
//

import Foundation
import GRDB

public typealias WADatabase = UUID

public enum WABackupError: Error {
    case directoryAccessError(error: Error)
    case noChatStorageFile
    case databaseConnectionError(error: Error)
    case databaseHasUnsupportedSchema(error: Error)
}


public struct ChatInfo: CustomStringConvertible, Encodable {
    public enum ChatType: String, Codable {
        case group
        case individual
        case channel
    }

    public let id: Int
    public let contactJid: String
    public let name: String
    public let numberMessages: Int
    public let lastMessageDate: Date
    public let chatType: ChatType
    public let isArchived: Bool
    
    init(id: Int, contactJid: String, name: String, 
         numberMessages: Int, lastMessageDate: Date, isArchived: Bool,
         isChannel: Bool = false) {
        self.id = id
        self.contactJid = contactJid
        self.name = name
        self.numberMessages = numberMessages
        self.lastMessageDate = lastMessageDate
        self.isArchived = isArchived
        if isChannel {
            self.chatType = .channel
        } else {
            self.chatType = contactJid.hasSuffix("@g.us") ? .group : .individual
        }
    }

    public var description: String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .medium
        let localDateString = dateFormatter.string(from: lastMessageDate)

        return "Chat: ID - \(id), ContactJid - \(contactJid), " 
            + "Name - \(name), Number of Messages - \(numberMessages), "
            + "Last Message Date - \(localDateString), "
            + "Chat Type - \(chatType.rawValue), "
            + "Is Archived - \(isArchived)"
        }
}

public struct Reaction: Encodable {
    public let emoji: String
    public let senderPhone: String
}

enum SupportedMessageType: Int64, CaseIterable {
    case text = 0
    case image = 1
    case video = 2
    case audio = 3
    case contact = 4
    case location = 5
    case link = 7
    case doc = 8
    case status = 10
    case gif = 11
    case sticker = 15

    var description: String {
        switch self {
        case .text: return "Text"
        case .image: return "Image"
        case .video: return "Video"
        case .audio: return "Audio"
        case .contact: return "Contact"
        case .location: return "Location"
        case .link: return "Link"
        case .doc: return "Document"
        case .status: return "Status"
        case .gif: return "GIF"
        case .sticker: return "Sticker"
        }
    }

    // Get all supported message types as an array of Int64 values
    static var allValues: [Int64] {
        return Self.allCases.map { $0.rawValue }
    }
}

public struct MessageInfo: CustomStringConvertible, Encodable {
    public let id: Int
    public let chatId: Int
    public let message: String?
    public let date: Date
    public let isFromMe: Bool 
    public let messageType: String
    public var senderName: String?
    public var senderPhone: String?
    public var caption: String?
    public var replyTo: Int?
    public var mediaFilename: String?
    public var reactions: [Reaction]?
    public var error: String?
    public var seconds: Int?
    public var latitude: Double?
    public var longitude: Double?

    public var description: String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .medium
        let localDateString = dateFormatter.string(from: date)

        return """
        Message: ID - \(id), IsFromMe - \(isFromMe), Message - 
        \(message ?? ""), Date - \(localDateString)
        """
    }
}

public struct ContactInfo: CustomStringConvertible, Encodable, Hashable {
    public let name: String
    public let phone: String
    public var photoFilename: String?
    public var thumbnailFilename: String?

    public var description: String {
        return "Contact: Phone - \(phone), Name - \(name)"
    }

    // Custom Hashable implementation to use only the phone number
    public func hash(into hasher: inout Hasher) {
        hasher.combine(phone)
    }

    // Custom Equatable implementation to use only the phone number
    public static func == (lhs: ContactInfo, rhs: ContactInfo) -> Bool {
        return lhs.phone == rhs.phone
    }
}

public protocol WABackupDelegate: AnyObject {
    func didWriteMediaFile(fileName: String)
}

public class WABackup {
    var phoneBackup = BackupManager()
    public weak var delegate: WABackupDelegate?

    // We allow to connect to more than one ChatStorage.sqlite file at the same time
    // The key is the backup identifier
    private var chatDatabases: [WADatabase: DatabaseQueue] = [:]
    private var iPhoneBackups: [WADatabase: IPhoneBackup] = [:]
    private var ownerJidByDatabase: [WADatabase: String?] = [:]

    // Modified initializer to accept a custom backup path
    public init(backupPath: String = "~/Library/Application Support/MobileSync/Backup/") {
        self.phoneBackup = BackupManager(backupPath: backupPath)
    }
    
    // The function needs permission to access 
    // ~/Library/Application Support/MobileSync/Backup/
    // Go to System Preferences -> Security & Privacy -> Full Disk Access
    public func getBackups() throws -> BackupFetchResult {
        do {
            return try phoneBackup.getBackups()
        } catch {
            throw WABackupError.directoryAccessError(error: error)
        }
    }

    //------------------------------------
    // connectChatStorageDb BEGINS
    //------------------------------------

    // Obtains the URL of the ChatStorage.sqlite file in a backup and
    // associates it with the backup identifier. The API can be connected to
    // more than one ChatStorage.sqlite file at the same time.
    public func connectChatStorageDb(from iPhoneBackup: IPhoneBackup) throws -> WADatabase {
        guard let chatStorageHash = iPhoneBackup.fetchWAFileHash(
                                            endsWith: "ChatStorage.sqlite") else {
            throw WABackupError.noChatStorageFile
        }

        let chatStorageUrl = iPhoneBackup.getUrl(fileHash: chatStorageHash)

        // Connect to the ChatStorage.sqlite file
        
        do {
            let chatStorageDb = try DatabaseQueue(path: chatStorageUrl.path)
            // Check the schema of the ChatStorage.sqlite file
            try checkSchema(of: chatStorageDb)
            // Generate a unique identifier for this database connection
            let uniqueIdentifier = WADatabase()
            // Store the connected DatabaseQueue and iPhoneBackup for future use
            chatDatabases[uniqueIdentifier] = chatStorageDb
            iPhoneBackups[uniqueIdentifier] = iPhoneBackup

            // Attempt to fetch the owner JID; if not found, set to nil
            // Use the helper method to fetch the owner JID
            let ownerJid = try chatStorageDb.read { db in
                try Message.fetchOwnerJid(from: db)
            }
            ownerJidByDatabase[uniqueIdentifier] = ownerJid
            return uniqueIdentifier
        } catch let error as WABackupError {
            // If the inner function throws WABackupError just rethrow it
            throw error
        } catch {
            throw WABackupError.databaseConnectionError(error: error)
        }
    }
    
    private func checkSchema(of dbQueue: DatabaseQueue) throws {
        // Define the expected tables and their respective fields
        let expectedSchema: [String: Set<String>] = [
            "ZWAMESSAGE": ["Z_PK", "ZTOJID", "ZMESSAGETYPE", "ZGROUPMEMBER",
                           "ZCHATSESSION", "ZTEXT", "ZMESSAGEDATE",
                           "ZFROMJID", "ZMEDIAITEM", "ZISFROMME",
                           "ZGROUPEVENTTYPE", "ZSTANZAID"],
            "ZWACHATSESSION": ["Z_PK", "ZCONTACTJID", "ZPARTNERNAME",
                               "ZLASTMESSAGEDATE", "ZMESSAGECOUNTER", "ZSESSIONTYPE", "ZARCHIVED"],
            "ZWAGROUPMEMBER": ["Z_PK", "ZMEMBERJID", "ZCONTACTNAME"],
            "ZWAPROFILEPUSHNAME": ["ZPUSHNAME", "ZJID"],
            "ZWAMEDIAITEM": ["Z_PK", "ZMETADATA", "ZTITLE", "ZMEDIALOCALPATH"],
            "ZWAMESSAGEINFO": ["ZRECEIPTINFO", "ZMESSAGE"]
        ]

        do {
            try dbQueue.read { db in
                for (table, expectedFields) in expectedSchema {
                    // Check if table exists
                    if try db.tableExists(table) {
                        // Fetch columns of the table
                        let columns = try db.columns(in: table)
                        let columnNames = Set(columns.map { $0.name.uppercased() })
                        
                        // Check if all expected fields exist in the table
                        if !expectedFields.isSubset(of: columnNames) {
                            print("Table \(table) does not have all expected fields")
                            return
                        }
                    } else {
                        throw WABackupError.databaseHasUnsupportedSchema(
                            error: DatabaseError(message: "Table \(table) does not exist"))
                    }
                }
            }
        } catch {
            throw WABackupError.databaseHasUnsupportedSchema(error: error)
        }
    }

        
    //------------------------------------
    // connectChatStorageDb ENDS
    //------------------------------------


    //------------------------------------
    // getChats BEGINS
    //------------------------------------

    public func getChats(from waDatabase: WADatabase) throws -> [ChatInfo] {
        guard let dbQueue = chatDatabases[waDatabase] else {
            throw WABackupError.databaseConnectionError(error: DatabaseError(message: "Database not found"))
        }
        let ownerJid = ownerJidByDatabase[waDatabase] ?? nil

        let chatInfos = try dbQueue.read { db -> [ChatInfo] in
            // Fetch all chat sessions using the data model
            let chatSessions = try ChatSession.fetchAllChats(from: db)

            // Map ChatSession instances to ChatInfo
            return chatSessions.map { chatSession in
                // Determine if the chat is a channel
                let isChannel = (chatSession.sessionType == 5)

                // Set chat name to "Me" if contactJid matches ownerJid
                var chatName = chatSession.partnerName
                if let userJid = ownerJid, chatSession.contactJid == userJid {
                    chatName = "Me"
                }

                return ChatInfo(
                    id: Int(chatSession.id),
                    contactJid: chatSession.contactJid,
                    name: chatName,
                    numberMessages: Int(chatSession.messageCounter),
                    lastMessageDate: chatSession.lastMessageDate,
                    isArchived: chatSession.isArchived,
                    isChannel: isChannel
                )
            }
        }

        return sortChatsByDate(chatInfos)
    }
    
    private func sortChatsByDate(_ chats: [ChatInfo]) -> [ChatInfo] {
        return chats.sorted { $0.lastMessageDate > $1.lastMessageDate }
    }
    
    //------------------------------------
    // getChats ENDS
    //------------------------------------

    //------------------------------------
    // getChatMessages BEGINS
    //------------------------------------

    public func getChatMessages(chatId: Int,
                                directoryToSaveMedia directory: URL?,
                                from waDatabase: WADatabase) throws -> [MessageInfo] {
        let dbQueue = chatDatabases[waDatabase]!
        let chatInfo = try fetchChatInfo(id: chatId, from: dbQueue) 
        let iPhoneBackup = iPhoneBackups[waDatabase]!

        let messages = try fetchChatMessages(chatId: chatId, type: chatInfo.chatType, 
                                         directoryToSaveMedia: directory, 
                                         iPhoneBackup: iPhoneBackup, from: dbQueue)
        return sortMessagesByDate(messages)
    }

    
    private func sortMessagesByDate(_ messages: [MessageInfo]) -> [MessageInfo] {
        return messages.sorted { $0.date > $1.date }
    }
    
    
    private func fetchChatInfo(id: Int, from dbQueue: DatabaseQueue) throws -> ChatInfo {
        return try dbQueue.read { db in
            let chatSession = try ChatSession.fetchChat(byId: id, from: db)
            
            let isChannel = (chatSession.sessionType == 5)
            let chatInfo = ChatInfo(
                id: Int(chatSession.id),
                contactJid: chatSession.contactJid,
                name: chatSession.partnerName,
                numberMessages: Int(chatSession.messageCounter),
                lastMessageDate: chatSession.lastMessageDate,
                isArchived: chatSession.isArchived,
                isChannel: isChannel
            )
            return chatInfo
        }
    }
    
    private func fetchChatMessages(chatId: Int,
                                   type: ChatInfo.ChatType,
                                   directoryToSaveMedia: URL?,
                                   iPhoneBackup: IPhoneBackup,
                                   from dbQueue: DatabaseQueue) throws -> [MessageInfo] {
        var messagesInfo: [MessageInfo] = []

        try dbQueue.read { db in
            let messages = try Message.fetchMessages(forChatId: chatId, from: db)
            for message in messages {
                guard let messageType = SupportedMessageType(rawValue: message.messageType) else {
                    continue // Skip unsupported message types
                }
                
                var messageText = message.text

                // **Reintroduce the business chat warning logic**
                if message.groupEventType == 38 {
                    messageText = "This is a business chat"
                }
                
                var messageInfo = MessageInfo(
                    id: Int(message.id),
                    chatId: Int(message.chatSessionId),
                    message: messageText,
                    date: message.date,
                    isFromMe: message.isFromMe,
                    messageType: messageType.description
                )

                // Fetch sender info
                if let senderInfo = try fetchSenderInfo(for: message, chatType: type, from: db) {
                    messageInfo.senderName = senderInfo.senderName
                    messageInfo.senderPhone = senderInfo.senderPhone
                }

                // Handle replies
                if let mediaItemId = message.mediaItemId,
                   let replyMessageId = try fetchReplyMessageId(mediaItemId: mediaItemId, from: db) {
                    messageInfo.replyTo = Int(replyMessageId)
                }

                // Handle media
                if let mediaItemId = message.mediaItemId,
                   let directory = directoryToSaveMedia {
                    if let mediaResult = try fetchMediaFilename(forMediaItem: mediaItemId,
                                                                from: iPhoneBackup,
                                                                toDirectory: directory,
                                                                from: db) {
                        switch mediaResult {
                        case .fileName(let fileName):
                            messageInfo.mediaFilename = fileName
                        case .error(let error):
                            messageInfo.error = error
                        }
                    }

                    // Fetch caption
                    if let caption = try fetchCaption(mediaItemId: mediaItemId, from: db) {
                        messageInfo.caption = caption
                    }

                    // Fetch duration
                    if messageType == .video || messageType == .audio {
                        messageInfo.seconds = try fetchSeconds(mediaItemId: mediaItemId, from: db)
                    }

                    // Fetch location
                    if messageType == .location {
                        let (latitude, longitude) = try fetchLocation(mediaItemId: mediaItemId, from: db)
                        messageInfo.latitude = latitude
                        messageInfo.longitude = longitude
                    }
                }

                // Fetch reactions
                messageInfo.reactions = try fetchReactions(forMessageId: Int(message.id), from: db)

                messagesInfo.append(messageInfo)
            }
        }

        return messagesInfo
    }
    
    typealias SenderInfo = (senderName: String?, senderPhone: String?)
    
    private func fetchSenderInfo(for message: Message, chatType: ChatInfo.ChatType, from db: Database) throws -> SenderInfo? {
        if message.isFromMe {
            return nil
        }

        switch chatType {
        case .group:
            if let memberId = message.groupMemberId,
               let groupMember = try GroupMember.fetchGroupMember(byId: memberId, from: db) {
                return try obtainSenderInfo(jid: groupMember.memberJid,
                                            contactNameGroupMember: groupMember.contactName,
                                            from: db)
            }
        case .individual, .channel:
            let chatSession = try ChatSession.fetchChat(byId: Int(message.chatSessionId), from: db)
            let senderPhone = chatSession.contactJid.extractedPhone
            let senderName = chatSession.partnerName
            return (senderName, senderPhone)
        }
        return nil
    }
    
    private func obtainSenderInfo(jid: String,
                                  contactNameGroupMember: String?,
                                  from db: Database) throws -> SenderInfo {
        let senderPhone = jid.extractedPhone
        if let senderName = try ChatSession.fetchChatSessionName(for: jid, from: db) {
            return (senderName, senderPhone)
        } else if let pushName = try ProfilePushName.fetchProfilePushName(for: jid, from: db) {
            return ("~" + pushName, senderPhone)
        } else {
            return (contactNameGroupMember, senderPhone)
        }
    }
    
    private func fetchReplyMessageId(mediaItemId: Int64,
                                     from db: Database) throws -> Int64? {
        do {
            let mediaItemRow = try Row.fetchOne(db, sql: """
                SELECT ZMETADATA FROM ZWAMEDIAITEM WHERE Z_PK = ?
                """, arguments: [mediaItemId])
            
            if let binaryData = mediaItemRow?["ZMETADATA"] as? Data {
                if let stanzaId = parseReplyMetadata(blob: binaryData) {
                    return try fetchOriginalMessageId(stanzaId: stanzaId, from: db)
                }
            }
            return nil
        } catch {
            throw WABackupError.databaseConnectionError(error: error)
        }
    }

    // Returns the stanza id of the message that is being replied to
    private func parseReplyMetadata(blob: Data) -> String? {
        let start = blob.startIndex.advanced(by: 2)
        var end: Int? = nil
        let endMarker: [UInt8] = [0x32, 0x1A] // hexadecimal 32 1A
        let endMarkerMe: [UInt8] = [0x9A, 0x01] // hexadecimal 9A 01 if the message
                                                // is sent by me

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
            // ASCII space is 32 (0x20) and characters less than this
            // are control characters.
            if asciiValue <= 0x20 {
                break
            }
            stanzaIDEnd = i
        }

        let stanzaIDRange = stanzaIDEnd..<endIndex
        let stanzaIDData = blob.subdata(in: stanzaIDRange)
        return String(data: stanzaIDData, encoding: .utf8)
    }

    private func fetchOriginalMessageId(stanzaId: String, from db: Database) throws -> Int64? {
        do {
            let messageRow = try Row.fetchOne(db, sql: """
                SELECT Z_PK FROM ZWAMESSAGE WHERE ZSTANZAID = ?
                """, arguments: [stanzaId])
            return messageRow?["Z_PK"] as? Int64
        } catch {
            throw WABackupError.databaseConnectionError(error: error)
        }
    }
        
    enum MediaFilename {
        case fileName(String)
        case error(String)
    }

    private func fetchMediaFilename(forMediaItem mediaItemId: Int64,
                                    from iPhoneBackup: IPhoneBackup,
                                    toDirectory directoryURL: URL,
                                    from db: Database) throws -> MediaFilename? {
        do {
            if let mediaItemRow = try Row.fetchOne(db, sql: """
            SELECT ZMEDIALOCALPATH FROM ZWAMEDIAITEM WHERE Z_PK = ?
            """, arguments: [mediaItemId]),
            let mediaLocalPath = mediaItemRow["ZMEDIALOCALPATH"] as? String {

                guard let hashFile = iPhoneBackup.fetchWAFileHash(
                    endsWith: mediaLocalPath) else {
                    return MediaFilename.error("Media file not found: \(mediaLocalPath)")
                }
                let fileName = URL(fileURLWithPath: mediaLocalPath).lastPathComponent
                let mediaFileName = try copyMediaFile(hashFile: hashFile, fileName: fileName, to: directoryURL, from: iPhoneBackup)
                return MediaFilename.fileName(mediaFileName)
            }
            return nil
        } catch let error as WABackupError {
            // Error thrown by the copy function
            throw error
        } catch {
            // Other errors
            throw WABackupError.databaseConnectionError(error: error)
        }
    }
    
    private func copyMediaFile(hashFile: String, fileName: String, to directoryURL: URL, from iPhoneBackup: IPhoneBackup) throws -> String {
        let targetFileUrl = directoryURL.appendingPathComponent(fileName)
        try copy(hashFile: hashFile, toTargetFileUrl: targetFileUrl, from: iPhoneBackup)
        
        // Inform the delegate that a media file has been written
        delegate?.didWriteMediaFile(fileName: targetFileUrl.path)
        
        return targetFileUrl.lastPathComponent
    }
    
    private func copy(hashFile: String, toTargetFileUrl url: URL, from iPhoneBackup: IPhoneBackup) throws {
        let sourceFileUrl = iPhoneBackup.getUrl(fileHash: hashFile)
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: url.path) {
            try fileManager.copyItem(at: sourceFileUrl, to: url)
        }
    }
    
    private func fetchCaption(mediaItemId: Int64, from db: Database) throws -> String? {
        do {
            let mediaItemRow = try Row.fetchOne(db, sql: """
                SELECT ZTITLE FROM ZWAMEDIAITEM WHERE Z_PK = ?
                """, arguments: [mediaItemId])
            if let caption = mediaItemRow?["ZTITLE"] as? String, !caption.isEmpty {
                return caption
            }
            return nil
        } catch {
            throw WABackupError.databaseConnectionError(error: error)
        }
    }
    
    private func fetchSeconds(mediaItemId: Int64, from db: Database) throws -> Int {
        do {
            let mediaItemRow = try Row.fetchOne(db, sql: """
                SELECT ZMOVIEDURATION FROM ZWAMEDIAITEM WHERE Z_PK = ?
                """, arguments: [mediaItemId])
            if let seconds = mediaItemRow?["ZMOVIEDURATION"] as? Int64 {
                return Int(seconds)
            }
            return 0
        } catch {
            throw WABackupError.databaseConnectionError(error: error)
        }
    }

    private func fetchLocation(mediaItemId: Int64, from db: Database) throws -> (Double, Double) {
        do {
            let mediaItemRow = try Row.fetchOne(db, sql: """
                SELECT ZLATITUDE, ZLONGITUDE FROM ZWAMEDIAITEM WHERE Z_PK = ?
                """, arguments: [mediaItemId])
            let latitude = mediaItemRow?["ZLATITUDE"] as? Double ?? 0
            let longitude = mediaItemRow?["ZLONGITUDE"] as? Double ?? 0
            return (latitude, longitude)
        } catch {
            throw WABackupError.databaseConnectionError(error: error)
        }
    }

    private func fetchReactions(forMessageId messageId: Int,
                                from db: Database) throws -> [Reaction]? {
        do {
            if let reactionsRow = try Row.fetchOne(db, sql: """
                SELECT ZRECEIPTINFO FROM ZWAMESSAGEINFO WHERE ZMESSAGE = ?
                """, arguments: [messageId]) {
                if let reactionsData = reactionsRow["ZRECEIPTINFO"] as? Data {
                    return extractReactions(from: reactionsData)
                }
            }
            return nil
        } catch {
            throw WABackupError.databaseConnectionError(error: error)
        }
    }
    
    // Extracts the reactions of a message from a byte array by scanning for emojis
    // and extracting the phone number of the sender that is present just before
    // the emoji.
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
                    if let emojiStr = String(bytes: emojiData, encoding: .utf8),
                       isSingleEmoji(emojiStr) {
                           let senderPhone = extractPhoneNumber(from: dataArray,
                                                                endIndex: i-2)
                           reactions.append(
                               Reaction(emoji: emojiStr,
                                        senderPhone: senderPhone ?? "Me"))
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
            (firstScalar.properties.isEmojiPresentation
                || scalars.contains { $0.properties.isEmojiPresentation })
    }

    // Extracts the phone number from a byte array of the
    // form: phone-number@s.whatsapp.net
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

    //------------------------------------
    // getChatMessages ENDS
    //------------------------------------

    
    //------------------------------------
    // getContacts BEGINS
    //------------------------------------

    // save all the contacts except the owner's
    // Por ahora este es el que funciona OK
    public func getContacts(directoryToSaveMedia directory: URL,
                            from waDatabase: WADatabase) throws -> [ContactInfo] {
        let dbQueue = chatDatabases[waDatabase]!
        let iPhoneBackup = iPhoneBackups[waDatabase]!

        // exclude the owner's contact
        let ownerProfile: ContactInfo? = try fetchOwnerProfile(from: dbQueue)
        let ownerPhone = ownerProfile?.phone

        let chats = try fetchChats(from: dbQueue, ownerJid: nil)
        let contactsSet = try extractContacts(from: chats, using: dbQueue, excludingPhone: ownerPhone)

        var updatedContacts: [ContactInfo] = []
        for contact in contactsSet {
            let updatedContact = try copyContactMedia(for: contact, from: iPhoneBackup, to: directory)
            updatedContacts.append(updatedContact)
        }
        
        return updatedContacts.sorted { $0.name < $1.name }
    }
    
    private func fetchOwnerProfile(from dbQueue: DatabaseQueue) throws -> ContactInfo {
        var ownerPhone = ""
        
        do {
            try dbQueue.read { db in
                if let ownerProfilePhone = try Message.fetchOwnerProfilePhone(from: db) {
                    ownerPhone = ownerProfilePhone.extractedPhone
                } else {
                    throw WABackupError.databaseConnectionError(
                        error: DatabaseError(message: "Owner profile not found"))
                }
            }
            return ContactInfo(name: "Me", phone: ownerPhone)
        } catch {
            throw WABackupError.databaseConnectionError(error: error)
        }
    }

    private func fetchChats(from dbQueue: DatabaseQueue, ownerJid: String?) throws -> [ChatInfo] {
        do {
            // Use the helper method to fetch all chat sessions
            let chatSessions = try dbQueue.read { db in
                try ChatSession.fetchAllChats(from: db)
            }

            // Map the fetched ChatSession instances to ChatInfo
            let chatInfos = chatSessions.map { chatSession -> ChatInfo in
                // Determine if the chat is a channel
                let isChannel = (chatSession.sessionType == 5)

                // Set chat name to "Me" if contactJid matches ownerJid
                var chatName = chatSession.partnerName
                if let userJid = ownerJid, chatSession.contactJid == userJid {
                    chatName = "Me"
                }

                return ChatInfo(
                    id: Int(chatSession.id),
                    contactJid: chatSession.contactJid,
                    name: chatName,
                    numberMessages: Int(chatSession.messageCounter),
                    lastMessageDate: chatSession.lastMessageDate,
                    isArchived: chatSession.isArchived,
                    isChannel: isChannel
                )
            }

            return sortChatsByDate(chatInfos)
        } catch {
            throw WABackupError.databaseConnectionError(error: error)
        }
    }
    
    private func extractContacts(from chats: [ChatInfo],
                                 using dbQueue: DatabaseQueue,
                                 excludingPhone: String?) throws -> Set<ContactInfo> {
        var contactsSet: Set<ContactInfo> = []
        for chat in chats {
            let phone = chat.contactJid.extractedPhone
            if phone != excludingPhone {
                let contact = ContactInfo(name: chat.name, phone: phone)
                contactsSet.insert(contact)
            }
            if chat.chatType == .group {
                    let groupContact = try fetchGroupMembersContacts(chatId: chat.id,
                                                                     from: dbQueue,
                                                                     excludingPhone: excludingPhone)
                    contactsSet.formUnion(groupContact)
            }
        }
        return contactsSet
    }

    private func copyContactMedia(for contact: ContactInfo,
                                  from iPhoneBackup: IPhoneBackup,
                                  to directory: URL) throws-> ContactInfo {
        var updatedContact = contact
        let contactPhotoFilename = "Media/Profile/\(contact.phone)"
        let filesNamesAndHashes =
            iPhoneBackup.fetchWAFileDetails(contains: contactPhotoFilename)
        
        // Copy the latest contact photo

        if let latestFile = getLatestFile(for: contactPhotoFilename,
                                          fileExtension: "jpg",
                                          files: filesNamesAndHashes) {
            let targetFilename = contact.phone + ".jpg"
            let targetFileUrl = directory.appendingPathComponent(targetFilename)
            try copy(hashFile: latestFile.fileHash,
                        toTargetFileUrl: targetFileUrl,
                        from: iPhoneBackup)

            // Inform the delegate that a media file has been written
            delegate?.didWriteMediaFile(fileName: targetFileUrl.path)

            updatedContact.photoFilename = targetFilename
        }

        // Copy the latest contact thumbnail
        if let latestFile = getLatestFile(for: contactPhotoFilename,
                                          fileExtension: "jpg",
                                          files: filesNamesAndHashes) {
            let targetFilename = contact.phone + ".jpg"
            updatedContact.photoFilename = try copyMediaFile(hashFile: latestFile.fileHash, fileName: targetFilename, to: directory, from: iPhoneBackup)
        }
        return updatedContact
    }

    private enum SenderIdentifier {
        case chatSession(chatId: Int)
        case groupMember(memberId: Int)
    }
    
    // Fetch the contact info of the participants of a gruop chat
    private func fetchGroupMembersContacts(chatId: Int,
                                           from dbQueue: DatabaseQueue,
                                           excludingPhone: String?) throws -> Set<ContactInfo> {
        var contactsSet: Set<ContactInfo> = []
        do {
            try dbQueue.read { db in
                // Fetch all distinct group member IDs for the given chat session
                let groupMemberIds = try GroupMember.fetchGroupMemberIds(forChatId: chatId, from: db)
                
                for memberId in groupMemberIds {
                    // Fetch sender information using the existing fetchSenderInfo method
                    let (senderName, senderPhone) = try fetchSenderInfo(.groupMember(memberId: Int(memberId)), from: db)
                    
                    // Filter out contacts based on the excludingPhone criteria
                    if let phone = senderPhone, phone != excludingPhone {
                        let contact = ContactInfo(name: senderName ?? "", phone: phone)
                        contactsSet.insert(contact)
                    }
                }
            }
        } catch {
            throw WABackupError.databaseConnectionError(error: error)
        }
        return contactsSet
    }

    // Obtain the latest files for the given filename and file extension
    //     prefixFilename: the prefix of the file (the phone number),
    //                     e.g. 1234567890 or 1234567890-202302323 for a group chat
    //     fileExtension: the wanted extension of the file, (.jpg or .thumb)
    //     namesAndHashes: an array of tuples containing the real filenames
    //                     (phone number + sufix + extension) and the file hash
    //                     the suffix is the timestamp of the photo
    // The function returns a tuple containing the real filename and the file hash
    //    of the file with the latest suffix and the corresponding extension
    private func getLatestFile(for prefixFilename: String,
                               fileExtension: String,
                               files namesAndHashes: [FilenameAndHash])
                               -> (FilenameAndHash)? {

        guard !namesAndHashes.isEmpty else {
            return nil
        }

        var latestFile: FilenameAndHash?  = nil
        var latestTimeSuffix = 0

        for nameAndHash in namesAndHashes {
            if let timeSuffix = extractTimeSuffix(from: prefixFilename,
                                                  fileExtension: fileExtension,
                                                  fileName: nameAndHash.filename) {
                if timeSuffix > latestTimeSuffix {
                    latestFile = (nameAndHash.filename, nameAndHash.fileHash)
                    latestTimeSuffix = timeSuffix
                }
            }
        }
        return latestFile
    }
    
    private func extractTimeSuffix(from prefixFilename: String,
                                   fileExtension: String,
                                   fileName: String) -> Int? {
        let pattern = prefixFilename + "-(\\d+)\\." + fileExtension
        let regex = try? NSRegularExpression(pattern: pattern)
        let fullRange = NSRange(fileName.startIndex..<fileName.endIndex, in: fileName)
        if let match = regex?.firstMatch(in: fileName, range: fullRange) {
            let timeSuffixString = (fileName as NSString).substring(with: match.range(at: 1))
            let timeSuffix = Int(timeSuffixString) ?? 0
            return timeSuffix
        }
        return nil
    }

    
    private func fetchSenderInfo(_ identifier: SenderIdentifier, from db: Database) throws -> SenderInfo {
        switch identifier {
        case .chatSession(let chatId):
            return try ChatSession.fetchSenderInfo(chatId: chatId, from: db)
        case .groupMember(let memberId):
            // Fetch raw sender info from GroupMember
            guard let rawSenderInfo = try GroupMember.fetchRawSenderInfo(memberId: memberId, from: db) else {
                return (nil, nil)
            }
            // Now call obtainSenderInfo with the raw data
            return try obtainSenderInfo(jid: rawSenderInfo.memberJid,
                                        contactNameGroupMember: rawSenderInfo.contactName,
                                        from: db)
        }
    }
    
    
    //------------------------------------
    // getContacts ENDS
    //------------------------------------

    
    //------------------------------------
    // getUserProfile BEGINS
    //------------------------------------

    
    public func getUserProfile(directoryToSaveMedia directory: URL,
                               from waDatabase: WADatabase) throws -> ContactInfo? {
        let dbQueue = chatDatabases[waDatabase]!
        let iPhoneBackup = iPhoneBackups[waDatabase]!
        
        var ownerProfile = try fetchOwnerProfile(from: dbQueue)
        let ownerPhotoTargetUrl = directory.appendingPathComponent("Photo.jpg")
        let ownerThumbnailTargetUrl = directory.appendingPathComponent("Photo.thumb")
        if let ownerPhotoHash = iPhoneBackup.fetchWAFileHash(
            endsWith: "Media/Profile/Photo.jpg") {
            try copy(hashFile: ownerPhotoHash, 
                        toTargetFileUrl: ownerPhotoTargetUrl, 
                        from: iPhoneBackup)

            // Inform the delegate that a media file has been written
            delegate?.didWriteMediaFile(fileName: ownerPhotoTargetUrl.path)

            ownerProfile.photoFilename = "Photo.jpg"
        }
        if let ownerThumbnailHash = iPhoneBackup.fetchWAFileHash(
            endsWith: "Media/Profile/Photo.thumb") {
            try copy(hashFile: ownerThumbnailHash, 
                        toTargetFileUrl: ownerThumbnailTargetUrl, 
                        from: iPhoneBackup)

            // Inform the delegate that a media file has been written
            delegate?.didWriteMediaFile(fileName: ownerThumbnailTargetUrl.path)

            ownerProfile.thumbnailFilename = "Photo.thumb"
        }
        return ownerProfile
    } 

    private func databaseQuestionMarks(count: Int) -> String {
        return Array(repeating: "?", count: count).joined(separator: ", ")
    }

    private func convertTimestampToDate(timestamp: Any) -> Date {
        if let timestamp = timestamp as? Double {
            return Date(timeIntervalSinceReferenceDate: timestamp)
        } else if let timestamp = timestamp as? Int64 {
            return Date(timeIntervalSinceReferenceDate: Double(timestamp))
        }
        return Date(timeIntervalSinceReferenceDate: 0)
    }

    //------------------------------------
    // getUserProfile BEGINS
    //------------------------------------

}


extension String {
    // Extracts phone from a JID string.
    var extractedPhone: String {
        return self.components(separatedBy: "@").first ?? ""
    }
}

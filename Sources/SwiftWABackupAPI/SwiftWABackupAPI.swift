//
//  SwiftWABackupAPI.swift
//
//
//  Created by Domingo Gallardo on 24/05/23.
//

import Foundation
import GRDB

public typealias WADatabase = UUID

public enum WABackupError: Error, LocalizedError {
    case directoryAccessError(underlyingError: Error)
    case noChatStorageFile
    case databaseConnectionError(underlyingError: Error)
    case databaseUnsupportedSchema(reason: String)
    case invalidBackup(url: URL, reason: String)
    case fileCopyError(source: URL, destination: URL, underlyingError: Error)
    case mediaNotFound(path: String)
    case messageNotFound(id: Int64)
    case chatNotFound(id: Int)
    case ownerProfileNotFound
    case unexpectedError(reason: String)
    
    public var errorDescription: String? {
        switch self {
        case .directoryAccessError(let error):
            return "Failed to access directory: \(error.localizedDescription)"
        case .noChatStorageFile:
            return "ChatStorage.sqlite file not found in the backup."
        case .databaseConnectionError(let error):
            return "Failed to connect to the database: \(error.localizedDescription)"
        case .databaseUnsupportedSchema(let reason):
            return "Database has an unsupported schema: \(reason)"
        case .invalidBackup(let url, let reason):
            return "Invalid backup at \(url.path): \(reason)"
        case .fileCopyError(let source, let destination, let error):
            return "Failed to copy file from \(source.path) to \(destination.path): \(error.localizedDescription)"
        case .mediaNotFound(let path):
            return "Media file not found at path: \(path)"
        case .messageNotFound(let id):
            return "Message with ID \(id) not found."
        case .chatNotFound(let id):
            return "Chat with ID \(id) not found."
        case .ownerProfileNotFound:
            return "Owner profile not found in the database."
        case .unexpectedError(let reason):
            return "An unexpected error occurred: \(reason)"
        }
    }
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

extension DatabaseQueue {
    func performRead<T>(_ block: (Database) throws -> T) throws -> T {
        do {
            return try self.read(block)
        } catch {
            throw WABackupError.databaseConnectionError(underlyingError: error)
        }
    }
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
            throw WABackupError.directoryAccessError(underlyingError: error)
        }
    }
    
    // Obtains the URL of the ChatStorage.sqlite file in a backup and
    // associates it with the backup identifier. The API can be connected to
    // more than one ChatStorage.sqlite file at the same time.
    public func connectChatStorageDb(from iPhoneBackup: IPhoneBackup) throws -> WADatabase {
        // Intentar obtener el hash del archivo ChatStorage.sqlite
        guard let chatStorageHash = try? iPhoneBackup.fetchWAFileHash(endsWith: "ChatStorage.sqlite") else {
            throw WABackupError.noChatStorageFile
        }
        
        let chatStorageUrl = iPhoneBackup.getUrl(fileHash: chatStorageHash)
        
        // Connect to the ChatStorage.sqlite file
        let chatStorageDb: DatabaseQueue
        do {
            chatStorageDb = try DatabaseQueue(path: chatStorageUrl.path)
            // Check the schema of the ChatStorage.sqlite file
            try checkSchema(of: chatStorageDb)
        } catch {
            throw WABackupError.databaseConnectionError(underlyingError: error)
        }
        
        // Generate a unique identifier for this database connection
        let uniqueIdentifier = WADatabase()
        
        // Store the connected DatabaseQueue and iPhoneBackup for future use
        chatDatabases[uniqueIdentifier] = chatStorageDb
        iPhoneBackups[uniqueIdentifier] = iPhoneBackup
        
        // Attempt to fetch the owner JID using performRead
        let ownerJid = try? chatStorageDb.performRead { db in
            try Message.fetchOwnerJid(from: db)
        }
        ownerJidByDatabase[uniqueIdentifier] = ownerJid
        
        return uniqueIdentifier
    }
    
    private func checkSchema(of dbQueue: DatabaseQueue) throws {
        do {
            try dbQueue.performRead { db in
                // Call the checkSchema method of each model
                try Message.checkSchema(in: db)
                try ChatSession.checkSchema(in: db)
                try GroupMember.checkSchema(in: db)
                try ProfilePushName.checkSchema(in: db)
                try MediaItem.checkSchema(in: db)
                try MessageInfoTable.checkSchema(in: db)
            }
        } catch {
            throw WABackupError.databaseUnsupportedSchema(reason: "Incorrect WA Database Schema")
        }
    }
}

// Chat-Related methods

extension WABackup {
    public func getChats(from waDatabase: WADatabase) throws -> [ChatInfo] {
        guard let dbQueue = chatDatabases[waDatabase] else {
            throw WABackupError.databaseConnectionError(underlyingError: DatabaseError(message: "Database not found"))
        }
        let ownerJid = ownerJidByDatabase[waDatabase] ?? nil
        
        let chatInfos = try dbQueue.performRead { db -> [ChatInfo] in
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
}

// Message-Related methods

extension WABackup {
    public func getChatMessages(chatId: Int, directoryToSaveMedia directory: URL?, from waDatabase: WADatabase) throws -> [MessageInfo] {
        let dbQueue = chatDatabases[waDatabase]!
        let chatInfo = try fetchChatInfo(id: chatId, from: dbQueue)
        let iPhoneBackup = iPhoneBackups[waDatabase]!
        
        // Fetch messages from the database
        let messages = try fetchMessagesFromDatabase(chatId: chatId, from: dbQueue)
        
        // Process messages
        let messagesInfo = try processMessages(messages, chatType: chatInfo.chatType, directoryToSaveMedia: directory, iPhoneBackup: iPhoneBackup, from: dbQueue)
        
        return sortMessagesByDate(messagesInfo)
    }
    
    private func fetchChatInfo(id: Int, from dbQueue: DatabaseQueue) throws -> ChatInfo {
        return try dbQueue.performRead { db in
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
    
    private func fetchMessagesFromDatabase(chatId: Int, from dbQueue: DatabaseQueue) throws -> [Message] {
        return try dbQueue.performRead { db in
            return try Message.fetchMessages(forChatId: chatId, from: db)
        }
    }
    
    private func processMessages(
        _ messages: [Message],
        chatType: ChatInfo.ChatType,
        directoryToSaveMedia: URL?,
        iPhoneBackup: IPhoneBackup,
        from dbQueue: DatabaseQueue
    ) throws -> [MessageInfo] {
        var messagesInfo: [MessageInfo] = []
        try dbQueue.read { db in
            for message in messages {
                let messageInfo = try processSingleMessage(
                    message,
                    chatType: chatType,
                    directoryToSaveMedia: directoryToSaveMedia,
                    iPhoneBackup: iPhoneBackup,
                    from: db
                )
                messagesInfo.append(messageInfo)
            }
        }
        return messagesInfo
    }
    
    private func processSingleMessage(_ message: Message, chatType: ChatInfo.ChatType, directoryToSaveMedia: URL?, iPhoneBackup: IPhoneBackup, from db: Database) throws -> MessageInfo {
        guard let messageType = SupportedMessageType(rawValue: message.messageType) else {
            throw WABackupError.unexpectedError(reason: "Unsupported message type")
        }
        
        var messageText = message.text
        
        // Handle group event types if necessary
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
        if let senderInfo = try fetchSenderInfo(for: message, chatType: chatType, from: db) {
            messageInfo.senderName = senderInfo.senderName
            messageInfo.senderPhone = senderInfo.senderPhone
        }
        
        // Handle replies
        if let replyMessageId = try fetchReplyMessageId(for: message, from: db) {
            messageInfo.replyTo = Int(replyMessageId)
        }
        
        // Handle media
        if let mediaInfo = try handleMedia(for: message, directoryToSaveMedia: directoryToSaveMedia, iPhoneBackup: iPhoneBackup, from: db) {
            messageInfo.mediaFilename = mediaInfo.mediaFilename
            messageInfo.caption = mediaInfo.caption
            messageInfo.seconds = mediaInfo.seconds
            messageInfo.latitude = mediaInfo.latitude
            messageInfo.longitude = mediaInfo.longitude
            messageInfo.error = mediaInfo.error
        }
        
        // Fetch reactions
        messageInfo.reactions = try fetchReactions(forMessageId: Int(message.id), from: db)
        
        return messageInfo
    }
    
    typealias SenderInfo = (senderName: String?, senderPhone: String?)
    
    private func fetchSenderInfo(for message: Message, chatType: ChatInfo.ChatType, from db: Database) throws -> SenderInfo? {
        if message.isFromMe {
            return nil
        }
        
        switch chatType {
        case .group:
            if let memberId = message.groupMemberId {
                return try fetchGroupMemberInfo(memberId: memberId, from: db)
            }
        case .individual, .channel:
            return try fetchIndividualChatSenderInfo(chatSessionId: message.chatSessionId, from: db)
        }
        return nil
    }
    
    private func fetchReplyMessageId(for message: Message, from db: Database) throws -> Int64? {
        if let mediaItemId = message.mediaItemId,
           let mediaItem = try MediaItem.fetchMediaItem(byId: mediaItemId, from: db),
           let stanzaId = mediaItem.extractReplyStanzaId() {
            return try Message.fetchMessageId(byStanzaId: stanzaId, from: db)
        }
        return nil
    }
    
    private func handleMedia(for message: Message, directoryToSaveMedia: URL?, iPhoneBackup: IPhoneBackup, from db: Database) throws -> (mediaFilename: String?, caption: String?, seconds: Int?, latitude: Double?, longitude: Double?, error: String?)? {
        guard let mediaItemId = message.mediaItemId else { return nil }
        
        var mediaFilename: String?
        var caption: String?
        var seconds: Int?
        var latitude: Double?
        var longitude: Double?
        var error: String?
        
        if let mediaResult = try fetchMediaFilename(forMediaItem: mediaItemId, from: iPhoneBackup, toDirectory: directoryToSaveMedia, from: db) {
            switch mediaResult {
            case .fileName(let fileName):
                mediaFilename = fileName
            case .error(let errMsg):
                error = errMsg
            }
        }
        
        // Fetch caption
        caption = try fetchCaption(mediaItemId: mediaItemId, from: db)
        
        // Fetch duration
        if let messageType = SupportedMessageType(rawValue: message.messageType), messageType == .video || messageType == .audio {
            seconds = try fetchDuration(mediaItemId: mediaItemId, from: db)
        }
        
        // Fetch location
        if let messageType = SupportedMessageType(rawValue: message.messageType), messageType == .location {
            (latitude, longitude) = try fetchLocation(mediaItemId: mediaItemId, from: db)
        }
        
        return (mediaFilename, caption, seconds, latitude, longitude, error)
    }
    
    private func fetchMediaFilename(forMediaItem mediaItemId: Int64,
                                    from iPhoneBackup: IPhoneBackup,
                                    toDirectory directoryURL: URL?,
                                    from db: Database) throws -> MediaFilename? {
        do {
            // Fetch the MediaItem using the new method
            if let mediaItem = try MediaItem.fetchMediaItem(byId: mediaItemId, from: db),
               let mediaLocalPath = mediaItem.localPath {
                
                guard let hashFile = try? iPhoneBackup.fetchWAFileHash(endsWith: mediaLocalPath) else {
                    return MediaFilename.error("Media file not found: \(mediaLocalPath)")
                }
                
                let fileName = URL(fileURLWithPath: mediaLocalPath).lastPathComponent
                let mediaFileName = try copyMediaFile(hashFile: hashFile,
                                                      fileName: fileName,
                                                      to: directoryURL,
                                                      from: iPhoneBackup)
                return MediaFilename.fileName(mediaFileName)
            }
            return nil
        } catch let error as WABackupError {
            // Error thrown by the copy function or MediaItem.fetchMediaItem
            throw error
        } catch {
            // Other errors
            throw WABackupError.databaseConnectionError(underlyingError: error)
        }
    }
    
    private func fetchGroupMemberInfo(memberId: Int64, from db: Database) throws -> SenderInfo? {
        if let groupMember = try GroupMember.fetchGroupMember(byId: memberId, from: db) {
            return try obtainSenderInfo(jid: groupMember.memberJid, contactNameGroupMember: groupMember.contactName, from: db)
        }
        return nil
    }
    
    private func fetchIndividualChatSenderInfo(chatSessionId: Int64, from db: Database) throws -> SenderInfo {
        let chatSession = try ChatSession.fetchChat(byId: Int(chatSessionId), from: db)
        let senderPhone = chatSession.contactJid.extractedPhone
        let senderName = chatSession.partnerName
        return (senderName, senderPhone)
    }
    
    private func fetchDuration(mediaItemId: Int64, from db: Database) throws -> Int? {
        if let mediaItem = try MediaItem.fetchMediaItem(byId: mediaItemId, from: db),
           let duration = mediaItem.movieDuration {
            return Int(duration)
        }
        return nil
    }
    
    private func fetchReactions(forMessageId messageId: Int, from db: Database) throws -> [Reaction]? {
        // Fetch the MessageInfoTable using the new method
        if let messageInfo = try MessageInfoTable.fetchMessageInfo(byMessageId: messageId, from: db),
           let reactionsData = messageInfo.receiptInfo {
            return extractReactions(from: reactionsData)
        }
        return nil
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
    
    private func fetchCaption(mediaItemId: Int64, from db: Database) throws -> String? {
        do {
            if let mediaItem = try MediaItem.fetchMediaItem(byId: mediaItemId, from: db),
               let caption = mediaItem.title, !caption.isEmpty {
                return caption
            }
            return nil
        } catch let error as WABackupError {
            throw error
        } catch {
            throw WABackupError.databaseConnectionError(underlyingError: error)
        }
    }
    
    private func fetchLocation(mediaItemId: Int64, from db: Database) throws -> (Double, Double) {
        do {
            if let mediaItem = try MediaItem.fetchMediaItem(byId: mediaItemId, from: db) {
                let latitude = mediaItem.latitude ?? 0.0
                let longitude = mediaItem.longitude ?? 0.0
                return (latitude, longitude)
            }
            return (0.0, 0.0)
        } catch let error as WABackupError {
            throw error
        } catch {
            throw WABackupError.databaseConnectionError(underlyingError: error)
        }
    }
    
    enum MediaFilename {
        case fileName(String)
        case error(String)
    }
    
    private func copyMediaFile(hashFile: String, fileName: String, to directoryURL: URL?, from iPhoneBackup: IPhoneBackup) throws -> String {
        if let directoryURL = directoryURL {
            let targetFileUrl = directoryURL.appendingPathComponent(fileName)
            try copy(hashFile: hashFile, toTargetFileUrl: targetFileUrl, from: iPhoneBackup)
        }
        // Inform the delegate that a media file has been written
        delegate?.didWriteMediaFile(fileName: fileName)
        return fileName
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
    
    
    private func sortMessagesByDate(_ messages: [MessageInfo]) -> [MessageInfo] {
        return messages.sorted { $0.date > $1.date }
    }
    
    // If url is nil do nothing, it's not an error
    private func copy(hashFile: String, toTargetFileUrl url: URL?, from iPhoneBackup: IPhoneBackup) throws {
        guard let url = url else {
            return
        }
        let sourceFileUrl = iPhoneBackup.getUrl(fileHash: hashFile)
        let fileManager = FileManager.default
        // If the file already exists do nothing, it's not an error
        if !fileManager.fileExists(atPath: url.path) {
            do {
                try fileManager.copyItem(at: sourceFileUrl, to: url)
            } catch {
                throw WABackupError.fileCopyError(source: sourceFileUrl, destination: url, underlyingError: error)
            }
        }
    }
}

// Contact-Related methods

extension WABackup {
    // save all the contacts except the owner's
    public func getContacts(directoryToSaveMedia directory: URL?, from waDatabase: WADatabase) throws -> [ContactInfo] {
        let dbQueue = chatDatabases[waDatabase]!
        let iPhoneBackup = iPhoneBackups[waDatabase]!
        let updatedContacts = try dbQueue.performRead { db in
            let ownerProfile = try fetchOwnerProfile(from: db)
            let chats = try fetchAllChats(from: db)
            let contactsSet = try extractContacts(from: chats,
                                                  excludingPhone: ownerProfile.phone,
                                                  from: db)
            var updatedContacts: [ContactInfo] = []
            for contact in contactsSet {
                let updatedContact = try copyContactMedia(for: contact, from: iPhoneBackup, to: directory)
                updatedContacts.append(updatedContact)
            }
            return updatedContacts.sorted { $0.name < $1.name }
        }
        return updatedContacts
    }
    
    private func fetchOwnerProfile(from db: Database) throws -> ContactInfo {
        var ownerPhone = ""
        if let ownerProfilePhone = try Message.fetchOwnerProfilePhone(from: db) {
            ownerPhone = ownerProfilePhone.extractedPhone
            return ContactInfo(name: "Me", phone: ownerPhone)
        } else {
            throw WABackupError.ownerProfileNotFound
        }
    }
    
    private func fetchAllChats(from db: Database) throws -> [ChatInfo] {
        let chatSessions = try ChatSession.fetchAllChats(from: db)
        return chatSessions.map { chatSession in
            let isChannel = (chatSession.sessionType == 5)
            return ChatInfo(
                id: Int(chatSession.id),
                contactJid: chatSession.contactJid,
                name: chatSession.partnerName,
                numberMessages: Int(chatSession.messageCounter),
                lastMessageDate: chatSession.lastMessageDate,
                isArchived: chatSession.isArchived,
                isChannel: isChannel
            )
        }
    }
    
    private func extractContacts(from chats: [ChatInfo],
                                 excludingPhone: String?,
                                 from db: Database) throws -> Set<ContactInfo> {
        var contactsSet: Set<ContactInfo> = []
        for chat in chats {
            let phone = chat.contactJid.extractedPhone
            if phone != excludingPhone {
                let contact = ContactInfo(name: chat.name, phone: phone)
                contactsSet.insert(contact)
            }
            if chat.chatType == .group {
                let groupContacts = try fetchGroupMembersContacts(chatId: chat.id,
                                                                  excludingPhone: excludingPhone,
                                                                  from: db)
                contactsSet.formUnion(groupContacts)
            }
        }
        return contactsSet
    }
    
    private func fetchGroupMembersContacts(chatId: Int,
                                           excludingPhone: String?,
                                           from db: Database) throws -> Set<ContactInfo> {
        var contactsSet: Set<ContactInfo> = []
        let groupMemberIds = try GroupMember.fetchGroupMemberIds(forChatId: chatId, from: db)
        for memberId in groupMemberIds {
            if let senderInfo = try fetchGroupMemberInfo(memberId: memberId, from: db),
               let phone = senderInfo.senderPhone, phone != excludingPhone {
                let contact = ContactInfo(name: senderInfo.senderName ?? "", phone: phone)
                contactsSet.insert(contact)
            }
        }
        return contactsSet
    }
    
    private func copyContactMedia(for contact: ContactInfo, from iPhoneBackup: IPhoneBackup, to directory: URL?) throws -> ContactInfo {
        var updatedContact = contact
        let contactPhotoFilename = "Media/Profile/\(contact.phone)"
        let filesNamesAndHashes = iPhoneBackup.fetchWAFileDetails(contains: contactPhotoFilename)
        
        if let latestFile = getLatestFile(for: contactPhotoFilename, fileExtension: "jpg", files: filesNamesAndHashes) {
            let targetFilename = contact.phone + ".jpg"
            let targetFileUrl = directory?.appendingPathComponent(targetFilename)
            try copy(hashFile: latestFile.fileHash, toTargetFileUrl: targetFileUrl, from: iPhoneBackup)
            delegate?.didWriteMediaFile(fileName: targetFilename)
            updatedContact.photoFilename = targetFilename
        }
        
        return updatedContact
    }
    
    private enum SenderIdentifier {
        case chatSession(chatId: Int)
        case groupMember(memberId: Int)
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
}

// UserProfile-Related methods

extension WABackup {
    public func getUserProfile(directoryToSaveMedia directory: URL,
                               from waDatabase: WADatabase) throws -> ContactInfo? {
        let dbQueue = chatDatabases[waDatabase]!
        let iPhoneBackup = iPhoneBackups[waDatabase]!

        var ownerProfile = try dbQueue.performRead { db in
            try fetchOwnerProfile(from: db)
        }
        let ownerPhotoTargetUrl = directory.appendingPathComponent("Photo.jpg")
        let ownerThumbnailTargetUrl = directory.appendingPathComponent("Photo.thumb")

        // Intentar obtener y copiar la foto de perfil
        let ownerPhotoHash = try iPhoneBackup.fetchWAFileHash(endsWith: "Media/Profile/Photo.jpg")
        try copy(hashFile: ownerPhotoHash,
                 toTargetFileUrl: ownerPhotoTargetUrl,
                 from: iPhoneBackup)

        // Informar al delegado que un archivo de medios ha sido escrito
        delegate?.didWriteMediaFile(fileName: ownerPhotoTargetUrl.path)
        ownerProfile.photoFilename = "Photo.jpg"

        // Intentar obtener y copiar la miniatura de perfil
        let ownerThumbnailHash = try iPhoneBackup.fetchWAFileHash(endsWith: "Media/Profile/Photo.thumb")
        try copy(hashFile: ownerThumbnailHash,
                 toTargetFileUrl: ownerThumbnailTargetUrl,
                 from: iPhoneBackup)

        // Informar al delegado que un archivo de medios ha sido escrito
        delegate?.didWriteMediaFile(fileName: ownerThumbnailTargetUrl.path)
        ownerProfile.thumbnailFilename = "Photo.thumb"
        
        return ownerProfile
    }
}


extension String {
    // Extracts phone from a JID string.
    var extractedPhone: String {
        return self.components(separatedBy: "@").first ?? ""
    }
}

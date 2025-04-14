//
//  SwiftWABackupAPI.swift
//
//  Created by Domingo Gallardo on 24/05/23.
//
//  This module provides an API for accessing and processing WhatsApp databases
//  extracted from iOS backups. It includes functionality for reading chats,
//  messages, contacts, and associated media files.

import Foundation
import GRDB

/// Errors that can occur while accessing or processing WhatsApp backups.
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
        // Provides user-friendly error descriptions.
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

/// Represents information about a WhatsApp chat.
public struct ChatInfo: CustomStringConvertible, Encodable {
    /// The type of chat (group or individual)
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
    public let isArchived: Bool
    
    /// Initializes a new `ChatInfo` instance.
    init(id: Int, contactJid: String, name: String,
         numberMessages: Int, lastMessageDate: Date, isArchived: Bool) {
        self.id = id
        self.contactJid = contactJid
        self.name = name
        self.numberMessages = numberMessages
        self.lastMessageDate = lastMessageDate
        self.isArchived = isArchived
        self.chatType = contactJid.hasSuffix("@g.us") ? .group : .individual
        }

    public var description: String {
        // Provides a human-readable description of the chat.
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

/// Represents a reaction to a message.
public struct Reaction: Encodable {
    public let emoji: String
    public let senderPhone: String
}

/// Supported message types in WhatsApp.
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
        // Provides a string representation of the message type.
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

    /// Returns all supported message types as an array of raw values.
    static var allValues: [Int64] {
        return Self.allCases.map { $0.rawValue }
    }
}

/// Represents information about a WhatsApp message.
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
        // Provides a human-readable description of the message.
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .medium
        let localDateString = dateFormatter.string(from: date)

        return """
        Message: ID - \(id), IsFromMe - \(isFromMe), Message - \
        \(message ?? ""), Date - \(localDateString)
        """
    }
}

/// Represents a contact's information.
public struct ContactInfo: CustomStringConvertible, Encodable, Hashable {
    public let name: String
    public let phone: String
    public var photoFilename: String?
    public var thumbnailFilename: String?

    public var description: String {
        return "Contact: Phone - \(phone), Name - \(name)"
    }

    // Hashable conformance to use in sets or as dictionary keys.
    public func hash(into hasher: inout Hasher) {
        hasher.combine(phone)
    }

    public static func == (lhs: ContactInfo, rhs: ContactInfo) -> Bool {
        return lhs.phone == rhs.phone
    }
}

/// Protocol to notify delegate about media file operations.
public protocol WABackupDelegate: AnyObject {
    /// Called when a media file has been written.
    func didWriteMediaFile(fileName: String)
}

/// Extension to safely perform read operations on the database queue.
extension DatabaseQueue {
    func performRead<T>(_ block: (Database) throws -> T) throws -> T {
        do {
            return try self.read(block)
        } catch {
            throw WABackupError.databaseConnectionError(underlyingError: error)
        }
    }
}

/// Main class to interact with WhatsApp backups.
public class WABackup {
    var phoneBackup = BackupManager()
    public weak var delegate: WABackupDelegate?
    
    private var chatDatabase: DatabaseQueue?
    private var iPhoneBackup: IPhoneBackup?
    private var ownerJid: String?
    
    /// Initializes the backup manager with an optional custom backup path.
    public init(backupPath: String = "~/Library/Application Support/MobileSync/Backup/") {
        self.phoneBackup = BackupManager(backupPath: backupPath)
    }
    
    /// Retrieves available iPhone backups.
    /// - Throws: `directoryAccessError` if the backup directory cannot be accessed.
    public func getBackups() throws -> BackupFetchResult {
        do {
            return try phoneBackup.getBackups()
        } catch {
            throw WABackupError.directoryAccessError(underlyingError: error)
        }
    }
    
    /// Connects to the ChatStorage.sqlite database from an iPhone backup.
    /// - Throws: An error if the ChatStorage.sqlite file is not found or the database cannot be connected.
    public func connectChatStorageDb(from backup: IPhoneBackup) throws {
        let chatStorageHash = try backup.fetchWAFileHash(endsWith: "ChatStorage.sqlite")
        let chatStorageUrl = backup.getUrl(fileHash: chatStorageHash)
        let dbQueue = try DatabaseQueue(path: chatStorageUrl.path)

        try checkSchema(of: dbQueue)

        self.chatDatabase = dbQueue
        self.iPhoneBackup = backup
        self.ownerJid = try dbQueue.performRead { try Message.fetchOwnerJid(from: $0) }
    }
    
    /// Validates the schema of the WhatsApp database.
    /// - Throws: An error if the schema is unsupported.
    private func checkSchema(of dbQueue: DatabaseQueue) throws {
        do {
            try dbQueue.performRead { db in
                // Check the schema for each relevant table.
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

// MARK: - Chat-Related Methods

extension WABackup {
    /// Retrieves all chats from the connected WhatsApp database.
    /// - Returns: An array of `ChatInfo` objects.
    /// - Throws: An error if the database is not connected.
    public func getChats() throws -> [ChatInfo] {
        guard let dbQueue = chatDatabase else {
            throw WABackupError.databaseConnectionError(
                underlyingError: DatabaseError(message: "Database not connected")
            )
        }

        let chatInfos = try dbQueue.performRead { db -> [ChatInfo] in
            let chatSessions = try ChatSession.fetchAllChats(from: db)

            return chatSessions.compactMap { chatSession in
                guard chatSession.sessionType != 5 else {
                    return nil
                }

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
                    isArchived: chatSession.isArchived
                )
            }
        }

        return sortChatsByDate(chatInfos)
    }
    
    /// Sorts chats by their last message date in descending order.
    private func sortChatsByDate(_ chats: [ChatInfo]) -> [ChatInfo] {
        return chats.sorted { $0.lastMessageDate > $1.lastMessageDate }
    }
}

// MARK: - Message-Related Methods

extension WABackup {
    /// Retrieves messages for a specific chat.
    /// - Parameters:
    ///   - chatId: The chat identifier.
    ///   - directory: Optional directory to save media files.
    /// - Returns: An array of `MessageInfo` objects.
    /// - Throws: An error if messages cannot be fetched or processed.
    public func getChatMessages(chatId: Int, directoryToSaveMedia directory: URL?) throws -> ([MessageInfo], [ContactInfo]) {
        // 1. Verificar base de datos y backup
        guard let dbQueue = chatDatabase,
              let iPhoneBackup = iPhoneBackup else {
            throw WABackupError.databaseConnectionError(
                underlyingError: DatabaseError(message: "Database or backup not found")
            )
        }

        // 2. Obtener chatInfo y mensajes
        let chatInfo = try fetchChatInfo(id: chatId, from: dbQueue)
        let messages = try fetchMessagesFromDatabase(chatId: chatId, from: dbQueue)
        let processedMessages = try processMessages(
            messages,
            chatType: chatInfo.chatType,
            directoryToSaveMedia: directory,
            iPhoneBackup: iPhoneBackup,
            from: dbQueue
        )

        // 3. Crear el array de contactos
        var contacts: [ContactInfo] = []

        // 3.1 Añadir el usuario (owner)
        let ownerPhone: String
        if let userJid = ownerJid {
            ownerPhone = userJid.extractedPhone
        } else {
            ownerPhone = "" // o lanzar error si se prefiere
        }
        var ownerContact = ContactInfo(name: "Me", phone: ownerPhone)
        if let directory = directory {
            ownerContact = try copyContactMedia(for: ownerContact, from: iPhoneBackup, to: directory)
        }
        contacts.append(ownerContact)

        // 3.2 Añadir otros participantes
        try dbQueue.read { db in
            switch chatInfo.chatType {
            case .individual:
                let otherPhone = chatInfo.contactJid.extractedPhone
                if otherPhone != ownerPhone {
                    var otherContact = ContactInfo(name: chatInfo.name, phone: otherPhone)
                    if let directory = directory {
                        otherContact = try copyContactMedia(for: otherContact, from: iPhoneBackup, to: directory)
                    }
                    contacts.append(otherContact)
                }

            case .group:
                let memberIds = try GroupMember.fetchGroupMemberIds(forChatId: chatId, from: db)
                for memberId in memberIds {
                    if let senderInfo = try fetchGroupMemberInfo(memberId: memberId, from: db),
                       let phone = senderInfo.senderPhone,
                       phone != ownerPhone {
                        var contact = ContactInfo(name: senderInfo.senderName ?? "", phone: phone)
                        if let directory = directory {
                            contact = try copyContactMedia(for: contact, from: iPhoneBackup, to: directory)
                        }
                        contacts.append(contact)
                    }
                }
            }
        }

        return (processedMessages, contacts)
    }
    
    /// Fetches chat information by ID.
    private func fetchChatInfo(id: Int, from dbQueue: DatabaseQueue) throws -> ChatInfo {
        return try dbQueue.performRead { db in
            let chatSession = try ChatSession.fetchChat(byId: id, from: db)
            
            return ChatInfo(
                id: Int(chatSession.id),
                contactJid: chatSession.contactJid,
                name: chatSession.partnerName,
                numberMessages: Int(chatSession.messageCounter),
                lastMessageDate: chatSession.lastMessageDate,
                isArchived: chatSession.isArchived)
        }
    }
    
    /// Fetches messages for a specific chat from the database.
    private func fetchMessagesFromDatabase(chatId: Int, from dbQueue: DatabaseQueue) throws -> [Message] {
        return try dbQueue.performRead { db in
            return try Message.fetchMessages(forChatId: chatId, from: db)
        }
    }
    
    /// Processes messages to create `MessageInfo` objects.
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
    
    /// Processes a single message to create a `MessageInfo` object.
    private func processSingleMessage(_ message: Message, chatType: ChatInfo.ChatType, directoryToSaveMedia: URL?, iPhoneBackup: IPhoneBackup, from db: Database) throws -> MessageInfo {
        guard let messageType = SupportedMessageType(rawValue: message.messageType) else {
            throw WABackupError.unexpectedError(reason: "Unsupported message type")
        }
        
        var messageText = message.text
        
        // Handle specific group event types.
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
        
        // Fetch sender info if the message is not from the user.
        if let senderInfo = try fetchSenderInfo(for: message, chatType: chatType, from: db) {
            messageInfo.senderName = senderInfo.senderName
            messageInfo.senderPhone = senderInfo.senderPhone
        }
        
        // Handle replies.
        if let replyMessageId = try fetchReplyMessageId(for: message, from: db) {
            messageInfo.replyTo = Int(replyMessageId)
        }
        
        // Handle media content.
        if let mediaInfo = try handleMedia(for: message, directoryToSaveMedia: directoryToSaveMedia, iPhoneBackup: iPhoneBackup, from: db) {
            messageInfo.mediaFilename = mediaInfo.mediaFilename
            messageInfo.caption = mediaInfo.caption
            messageInfo.seconds = mediaInfo.seconds
            messageInfo.latitude = mediaInfo.latitude
            messageInfo.longitude = mediaInfo.longitude
            messageInfo.error = mediaInfo.error
        }
        
        // Fetch reactions to the message.
        messageInfo.reactions = try fetchReactions(forMessageId: Int(message.id), from: db)
        
        return messageInfo
    }
    
    /// Sender name and sender phone
    typealias SenderInfo = (senderName: String?, senderPhone: String?)
    
    /// Fetches sender information for a message.
    private func fetchSenderInfo(for message: Message, chatType: ChatInfo.ChatType, from db: Database) throws -> SenderInfo? {
        if message.isFromMe {
            return nil
        }
        
        switch chatType {
        case .group:
            if let memberId = message.groupMemberId {
                return try fetchGroupMemberInfo(memberId: memberId, from: db)
            }
        case .individual:
            return try fetchIndividualChatSenderInfo(chatSessionId: message.chatSessionId, from: db)
        }
        return nil
    }
    
    /// Fetches the message ID that the current message is replying to.
    private func fetchReplyMessageId(for message: Message, from db: Database) throws -> Int64? {
        if let mediaItemId = message.mediaItemId,
           let mediaItem = try MediaItem.fetchMediaItem(byId: mediaItemId, from: db),
           let stanzaId = mediaItem.extractReplyStanzaId() {
            return try Message.fetchMessageId(byStanzaId: stanzaId, from: db)
        }
        return nil
    }
    
    /// Handles media content associated with a message.
    private func handleMedia(for message: Message, directoryToSaveMedia: URL?, iPhoneBackup: IPhoneBackup, from db: Database) throws -> (mediaFilename: String?, caption: String?, seconds: Int?, latitude: Double?, longitude: Double?, error: String?)? {
        guard let mediaItemId = message.mediaItemId else { return nil }
        
        var mediaFilename: String?
        var caption: String?
        var seconds: Int?
        var latitude: Double?
        var longitude: Double?
        var error: String?
        
        // Fetch and copy media file if needed.
        if let mediaResult = try fetchMediaFilename(forMediaItem: mediaItemId, from: iPhoneBackup, toDirectory: directoryToSaveMedia, from: db) {
            switch mediaResult {
            case .fileName(let fileName):
                mediaFilename = fileName
            case .error(let errMsg):
                error = errMsg
            }
        }
        
        // Fetch caption if available.
        caption = try fetchCaption(mediaItemId: mediaItemId, from: db)
        
        // Fetch duration for audio/video messages.
        if let messageType = SupportedMessageType(rawValue: message.messageType), messageType == .video || messageType == .audio {
            seconds = try fetchDuration(mediaItemId: mediaItemId, from: db)
        }
        
        // Fetch location data for location messages.
        if let messageType = SupportedMessageType(rawValue: message.messageType), messageType == .location {
            (latitude, longitude) = try fetchLocation(mediaItemId: mediaItemId, from: db)
        }
        
        return (mediaFilename, caption, seconds, latitude, longitude, error)
    }
    
    /// Fetches the media filename and copies the media file if necessary.
    private func fetchMediaFilename(forMediaItem mediaItemId: Int64,
                                    from iPhoneBackup: IPhoneBackup,
                                    toDirectory directoryURL: URL?,
                                    from db: Database) throws -> MediaFilename? {
        do {
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
            // Error thrown by the copy function or MediaItem.fetchMediaItem.
            throw error
        } catch {
            // Other errors.
            throw WABackupError.databaseConnectionError(underlyingError: error)
        }
    }
    
    /// Fetches group member information by member ID.
    private func fetchGroupMemberInfo(memberId: Int64, from db: Database) throws -> SenderInfo? {
        if let groupMember = try GroupMember.fetchGroupMember(byId: memberId, from: db) {
            return try obtainSenderInfo(jid: groupMember.memberJid, contactNameGroupMember: groupMember.contactName, from: db)
        }
        return nil
    }
    
    /// Fetches sender information for individual chats.
    private func fetchIndividualChatSenderInfo(chatSessionId: Int64, from db: Database) throws -> SenderInfo {
        let chatSession = try ChatSession.fetchChat(byId: Int(chatSessionId), from: db)
        let senderPhone = chatSession.contactJid.extractedPhone
        let senderName = chatSession.partnerName
        return (senderName, senderPhone)
    }
    
    /// Fetches the duration of media content.
    private func fetchDuration(mediaItemId: Int64, from db: Database) throws -> Int? {
        if let mediaItem = try MediaItem.fetchMediaItem(byId: mediaItemId, from: db),
           let duration = mediaItem.movieDuration {
            return Int(duration)
        }
        return nil
    }
    
    /// Fetches reactions to a message.
    private func fetchReactions(forMessageId messageId: Int, from db: Database) throws -> [Reaction]? {
        if let messageInfo = try MessageInfoTable.fetchMessageInfo(byMessageId: messageId, from: db),
           let reactionsData = messageInfo.receiptInfo {
            return extractReactions(from: reactionsData)
        }
        return nil
    }
    
    /// Extracts reactions from the receipt info data.
    private func extractReactions(from data: Data) -> [Reaction]? {
        var reactions: [Reaction] = []
        let dataArray = [UInt8](data)
        var i = 0
        
        while i < dataArray.count {
            // The byte before the emoji indicates the emoji length.
            let emojiLength = Int(dataArray[i])
            if emojiLength <= 28 {
                // Maximum possible length of an emoji is 28 bytes.
                i += 1
                let emojiEndIndex = i + emojiLength
                if emojiEndIndex <= dataArray.count {
                    let emojiData = dataArray[i..<emojiEndIndex]
                    if let emojiStr = String(bytes: emojiData, encoding: .utf8),
                       isSingleEmoji(emojiStr) {
                        // Extract the sender's phone number preceding the emoji.
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
    
    /// Checks if a string is a single emoji.
    private func isSingleEmoji(_ string: String) -> Bool {
        // Checks if the string represents a single emoji character or sequence.
        guard let firstScalar = string.unicodeScalars.first else {
            return false
        }
        return firstScalar.properties.isEmoji &&
            (firstScalar.properties.isEmojiPresentation
             || string.unicodeScalars.contains { $0.properties.isEmojiPresentation })
    }
    
    /// Fetches the caption for a media item.
    private func fetchCaption(mediaItemId: Int64, from db: Database) throws -> String? {
        if let mediaItem = try MediaItem.fetchMediaItem(byId: mediaItemId, from: db),
           let caption = mediaItem.title, !caption.isEmpty {
            return caption
        }
        return nil
    }
    
    /// Fetches location data for a media item.
    private func fetchLocation(mediaItemId: Int64, from db: Database) throws -> (Double, Double) {
        if let mediaItem = try MediaItem.fetchMediaItem(byId: mediaItemId, from: db) {
            let latitude = mediaItem.latitude ?? 0.0
            let longitude = mediaItem.longitude ?? 0.0
            return (latitude, longitude)
        }
        return (0.0, 0.0)
    }
    
    /// Enum representing the result of fetching a media filename.
    enum MediaFilename {
        case fileName(String)
        case error(String)
    }
    
    /// Copies a media file from the backup to a specified directory.
    private func copyMediaFile(hashFile: String, fileName: String, to directoryURL: URL?, from iPhoneBackup: IPhoneBackup) throws -> String {
        if let directoryURL = directoryURL {
            let targetFileUrl = directoryURL.appendingPathComponent(fileName)
            try copy(hashFile: hashFile, toTargetFileUrl: targetFileUrl, from: iPhoneBackup)
        }
        // Notify the delegate that a media file has been written.
        delegate?.didWriteMediaFile(fileName: fileName)
        return fileName
    }
    
    /// Obtains sender information based on the JID.
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
    
    /// Extracts the phone number from a byte array.
    private func extractPhoneNumber(from data: [UInt8], endIndex: Int) -> String? {
        let senderSuffix = "@s.whatsapp.net"
        let suffixData = Array(senderSuffix.utf8)
        var endIndex = endIndex - 1
        
        // Verify the sender suffix is present.
        var suffixEndIndex = suffixData.count - 1
        while suffixEndIndex >= 0 && endIndex >= 0 {
            if data[endIndex] != suffixData[suffixEndIndex] {
                return nil
            }
            suffixEndIndex -= 1
            endIndex -= 1
        }
        
        // If the sender suffix wasn't fully matched.
        if suffixEndIndex >= 0 {
            return nil
        }
        
        // Extract the phone number.
        var phoneNumberData: [UInt8] = []
        while endIndex >= 0 {
            let char = data[endIndex]
            if char < 48 || char > 57 { // ASCII '0' to '9'
                break
            }
            phoneNumberData.append(char)
            endIndex -= 1
        }
        
        // If no phone number was found.
        if phoneNumberData.isEmpty {
            return nil
        }
        
        // Convert the phone number data to a string.
        let phoneNumber = String(bytes: phoneNumberData.reversed(), encoding: .utf8)
        return phoneNumber
    }
    
    /// Sorts messages by date in descending order.
    private func sortMessagesByDate(_ messages: [MessageInfo]) -> [MessageInfo] {
        return messages.sorted { $0.date > $1.date }
    }
    
    /// Copies a file from the backup to a target URL if the URL is provided.
    private func copy(hashFile: String, toTargetFileUrl url: URL?, from iPhoneBackup: IPhoneBackup) throws {
        guard let url = url else {
            return
        }
        let sourceFileUrl = iPhoneBackup.getUrl(fileHash: hashFile)
        let fileManager = FileManager.default
        // If the file already exists, do nothing.
        if !fileManager.fileExists(atPath: url.path) {
            do {
                try fileManager.copyItem(at: sourceFileUrl, to: url)
            } catch {
                throw WABackupError.fileCopyError(source: sourceFileUrl, destination: url, underlyingError: error)
            }
        }
    }
}

// MARK: - Contact-Related Methods

extension WABackup {
    /// Retrieves contacts from the chats, excluding the owner's profile.
    /// - Parameters:
    ///   - chats: The list of chats to extract contacts from.
    ///   - directory: Optional directory to save contact media files.
    /// - Returns: An array of `ContactInfo` objects.
    /// - Throws: An error if contacts cannot be fetched or media files cannot be copied.
    public func getContacts(chats: [ChatInfo], directoryToSaveMedia directory: URL?) throws -> [ContactInfo] {
        guard let dbQueue = chatDatabase,
              let iPhoneBackup = iPhoneBackup else {
            throw WABackupError.databaseConnectionError(
                underlyingError: DatabaseError(message: "Database or backup not found")
            )
        }
        
        // Obtener el perfil del usuario y los contactos en una sola lectura
        let (_, contactsSet) = try dbQueue.performRead { db -> (ContactInfo, Set<ContactInfo>) in
            let ownerProfile = try fetchOwnerProfile(from: db)
            let contactsSet = try extractContacts(
                from: chats,
                excludingPhone: ownerProfile.phone,
                from: db
            )
            return (ownerProfile, contactsSet)
        }
        
        var updatedContacts: [ContactInfo] = []
        for contact in contactsSet {
            let updatedContact = try copyContactMedia(for: contact, from: iPhoneBackup, to: directory)
            updatedContacts.append(updatedContact)
        }
        
        return updatedContacts.sorted { $0.name < $1.name }
    }
    
    /// Fetches the owner's profile from the database.
    private func fetchOwnerProfile(from db: Database) throws -> ContactInfo {
        var ownerPhone = ""
        if let ownerProfilePhone = try Message.fetchOwnerProfilePhone(from: db) {
            ownerPhone = ownerProfilePhone.extractedPhone
            return ContactInfo(name: "Me", phone: ownerPhone)
        } else {
            throw WABackupError.ownerProfileNotFound
        }
    }
    
    /// Extracts contacts from chats, excluding a specific phone number.
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
    
    /// Fetches contacts from group members.
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
    
    /// Copies contact media files if available.
    private func copyContactMedia(for contact: ContactInfo, from iPhoneBackup: IPhoneBackup, to directory: URL?) throws -> ContactInfo {
        var updatedContact = contact
        let contactPhotoFilename = "Media/Profile/\(contact.phone)"
        let filesNamesAndHashes = iPhoneBackup.fetchWAFileDetails(contains: contactPhotoFilename)
        
        // Primero intenta jpg, si no existe intenta thumb
        let latestFile = getLatestFile(for: contactPhotoFilename, fileExtension: "jpg", files: filesNamesAndHashes)
        ?? getLatestFile(for: contactPhotoFilename, fileExtension: "thumb", files: filesNamesAndHashes)
        
        if let latestFile = latestFile {
            let targetFilename = contact.phone + (latestFile.filename.hasSuffix(".jpg") ? ".jpg" : ".thumb")
            let targetFileUrl = directory?.appendingPathComponent(targetFilename)
            try copy(hashFile: latestFile.fileHash, toTargetFileUrl: targetFileUrl, from: iPhoneBackup)
            delegate?.didWriteMediaFile(fileName: targetFilename)
            updatedContact.photoFilename = targetFilename
        }
        return updatedContact
    }
    
    /// Obtains the latest file for a given prefix and file extension.
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
    
    /// Extracts the time suffix from a filename.
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
}

// MARK: - UserProfile-Related Methods

extension WABackup {
    /// Retrieves the user's profile information and copies associated media.
    /// - Parameters:
    ///   - directory: The directory to save the profile media files.
    /// - Returns: A `ContactInfo` object with the user's profile information.
    /// - Throws: An error if the profile cannot be fetched or media files cannot be copied.
    public func getUserProfile(directoryToSaveMedia directory: URL) throws -> ContactInfo? {
        guard let dbQueue = chatDatabase,
              let iPhoneBackup = iPhoneBackup else {
            throw WABackupError.databaseConnectionError(
                underlyingError: DatabaseError(message: "Database or backup not found")
            )
        }
        
        var ownerProfile = try dbQueue.performRead { db in
            try fetchOwnerProfile(from: db)
        }
        
        let ownerPhotoTargetUrl = directory.appendingPathComponent("Photo.jpg")
        let ownerThumbnailTargetUrl = directory.appendingPathComponent("Photo.thumb")
        
        // Copiar foto de perfil
        let ownerPhotoHash = try iPhoneBackup.fetchWAFileHash(endsWith: "Media/Profile/Photo.jpg")
        try copy(hashFile: ownerPhotoHash,
                 toTargetFileUrl: ownerPhotoTargetUrl,
                 from: iPhoneBackup)
        delegate?.didWriteMediaFile(fileName: ownerPhotoTargetUrl.lastPathComponent)
        ownerProfile.photoFilename = "Photo.jpg"
        
        // Copiar thumbnail de perfil
        let ownerThumbnailHash = try iPhoneBackup.fetchWAFileHash(endsWith: "Media/Profile/Photo.thumb")
        try copy(hashFile: ownerThumbnailHash,
                 toTargetFileUrl: ownerThumbnailTargetUrl,
                 from: iPhoneBackup)
        delegate?.didWriteMediaFile(fileName: ownerThumbnailTargetUrl.lastPathComponent)
        ownerProfile.thumbnailFilename = "Photo.thumb"
        
        return ownerProfile
    }
}

// MARK: - String Extension

extension String {
    /// Extracts the phone number from a JID string.
    var extractedPhone: String {
        return self.components(separatedBy: "@").first ?? ""
    }
}

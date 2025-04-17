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
    public var photoFilename: String?
    
    /// Initializes a new `ChatInfo` instance.
    init(id: Int, contactJid: String, name: String,
         numberMessages: Int, lastMessageDate: Date, isArchived: Bool, photoFilename: String? = nil) {
        self.id = id
        self.contactJid = contactJid
        self.name = name
        self.numberMessages = numberMessages
        self.lastMessageDate = lastMessageDate
        self.isArchived = isArchived
        self.chatType = contactJid.hasSuffix("@g.us") ? .group : .individual
        self.photoFilename = photoFilename
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
            + "Is Archived - \(isArchived), "
            + "Photo Filename - \(photoFilename ?? "None")"
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

public typealias ChatDump = (chatInfo: ChatInfo, messages: [MessageInfo], contacts: [ContactInfo])

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
    
    private var mediaCopier: MediaCopier?
    
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
        self.mediaCopier = MediaCopier(backup: backup, delegate: delegate)   // ← NUEVO
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

// MARK: - Chat-Related Methods

    /// Retrieves all chats from the connected WhatsApp database.
    /// - Returns: An array of `ChatInfo` objects.
    /// - Throws: An error if the database is not connected.
    public func getChats(directoryToSavePhotos directory: URL? = nil) throws -> [ChatInfo] {
        guard let dbQueue = chatDatabase,
              let iPhoneBackup = iPhoneBackup else {
            throw WABackupError.databaseConnectionError(
                underlyingError: DatabaseError(message: "Database not connected")
            )
        }

        let chatInfos = try dbQueue.performRead { db -> [ChatInfo] in
            let chatSessions = try ChatSession.fetchAllChats(from: db)

            return chatSessions.compactMap { chatSession  -> ChatInfo? in
                guard chatSession.sessionType != 5 else {
                    return nil
                }

                var chatName = chatSession.partnerName
                if let userJid = ownerJid, chatSession.contactJid == userJid {
                    chatName = "Me"
                }

                var photoFilename: String? = nil
                if let directory = directory {
                    photoFilename = try? fetchChatPhotoFilename(
                        for: chatSession.contactJid,
                        chatId: Int(chatSession.id),
                        to: directory,
                        from: iPhoneBackup
                    )                }
                
                return ChatInfo(
                    id: Int(chatSession.id),
                    contactJid: chatSession.contactJid,
                    name: chatName,
                    numberMessages: Int(chatSession.messageCounter),
                    lastMessageDate: chatSession.lastMessageDate,
                    isArchived: chatSession.isArchived,
                    photoFilename: photoFilename
                )
            }
        }

        return sortChatsByDate(chatInfos)
    }
    
    /// Sorts chats by their last message date in descending order.
    private func sortChatsByDate(_ chats: [ChatInfo]) -> [ChatInfo] {
        return chats.sorted { $0.lastMessageDate > $1.lastMessageDate }
    }

// MARK: - Message-Related Methods

    /// Retrieves messages for a specific chat.
    /// - Parameters:
    ///   - chatId: The chat identifier.
    ///   - directory: Optional directory to save media files.
    /// - Returns: An array of `MessageInfo` objects.
    /// - Throws: An error if messages cannot be fetched or processed.
    public func getChat(chatId: Int, directoryToSaveMedia directory: URL?) throws -> ChatDump {
        guard let dbQueue = chatDatabase,
              let iPhoneBackup = iPhoneBackup else {
            throw WABackupError.databaseConnectionError(
                underlyingError: DatabaseError(message: "Database or backup not found")
            )
        }

        let chatInfo = try fetchChatInfo(id: chatId, from: dbQueue)
        let messages = try fetchMessagesFromDatabase(chatId: chatId, from: dbQueue)
        
        let processedMessages = try processMessages(
            messages,
            chatType: chatInfo.chatType,
            directoryToSaveMedia: directory,
            iPhoneBackup: iPhoneBackup,
            from: dbQueue
        )

        let contacts = try buildContactList(
            for: chatInfo,
            from: dbQueue,
            iPhoneBackup: iPhoneBackup,
            directory: directory
        )
        
        return (chatInfo, processedMessages, contacts)
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
    
    private func fetchMediaFilename(forMediaItem mediaItemId: Int64,
                                    from iPhoneBackup: IPhoneBackup,
                                    toDirectory directoryURL: URL?,
                                    from db: Database) throws -> MediaFilename? {
        if let mediaItem = try MediaItem.fetchMediaItem(byId: mediaItemId, from: db),
           let mediaLocalPath = mediaItem.localPath,
           let hashFile = try? iPhoneBackup.fetchWAFileHash(endsWith: mediaLocalPath) {

            let fileName = URL(fileURLWithPath: mediaLocalPath).lastPathComponent
            try mediaCopier?.copy(hash: hashFile,
                                  named: fileName,
                                  to: directoryURL)
            return .fileName(fileName)
        }
        return nil
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
    private func fetchReactions(forMessageId messageId: Int,
                                from db: Database) throws -> [Reaction]? {
        // Tras la refactorización, MessageInfoTable adoptó FetchableByID,
        // por lo que el método adecuado es `fetch(by:from:)`.
        if let messageInfo = try MessageInfoTable.fetch(by: messageId, from: db),
           let reactionsData = messageInfo.receiptInfo {
            return ReactionParser.parse(reactionsData)
        }
        return nil
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
    
    /// Obtains sender information based on the JID.
    private func obtainSenderInfo(jid: String,
                                  contactNameGroupMember: String?,
                                  from db: Database) throws -> SenderInfo {
        let senderPhone = jid.extractedPhone
        if let senderName = try ChatSession.fetchChatSessionName(for: jid, from: db) {
            return (senderName, senderPhone)
        } else if let pushName =  try ProfilePushName.pushName(for: jid, from: db) {
            return ("~" + pushName, senderPhone)
        } else {
            return (contactNameGroupMember, senderPhone)
        }
    }
    
    /// Sorts messages by date in descending order.
    private func sortMessagesByDate(_ messages: [MessageInfo]) -> [MessageInfo] {
        return messages.sorted { $0.date > $1.date }
    }

// MARK: - Contact-Related Methods

    /// Devuelve el nombre de archivo de la foto del chat y lo copia al directorio indicado.
    private func fetchChatPhotoFilename(for contactJid: String,
                                        chatId: Int,
                                        to directory: URL,
                                        from backup: IPhoneBackup) throws -> String? {

        // 1. Construir la ruta base según tipo de JID
        let basePath: String
        if contactJid.hasSuffix("@s.whatsapp.net") {
            basePath = "Media/Profile/\(contactJid.extractedPhone)"
        } else if contactJid.hasSuffix("@g.us") {
            let groupId = contactJid.components(separatedBy: "@").first ?? contactJid
            basePath = "Media/Profile/\(groupId)"
        } else {
            print("⚠️  ContactJid '\(contactJid)' has unsupported format. No image will be retrieved.")
            return nil
        }

        // 2. Localizar el fichero más reciente (.jpg o .thumb)
        let files = backup.fetchWAFileDetails(contains: basePath)
        guard let latest = getLatestFile(for: basePath, fileExtension: "jpg", files: files)
           ??  getLatestFile(for: basePath, fileExtension: "thumb", files: files) else {
            let type = contactJid.hasSuffix("@g.us") ? "Group" : "Individual"
            print("📭 No image found for \(type) chat [ID: \(chatId), JID: \(contactJid)]")
            return nil
        }

        // 3. Nombre destino “chat_<id>.ext” y copia mediante MediaCopier
        let ext       = latest.filename.hasSuffix(".jpg") ? ".jpg" : ".thumb"
        let fileName  = "chat_\(chatId)\(ext)"

        try mediaCopier?.copy(hash: latest.fileHash,
                              named: fileName,
                              to: directory) 

        return fileName
    }
    
    private func buildContactList(for chatInfo: ChatInfo,
                                  from dbQueue: DatabaseQueue,
                                  iPhoneBackup: IPhoneBackup,
                                  directory: URL?) throws -> [ContactInfo] {
        var contacts: [ContactInfo] = []

        // Añadir el usuario (owner)
        let ownerPhone: String = ownerJid?.extractedPhone ?? ""
        var ownerContact = ContactInfo(name: "Me", phone: ownerPhone)
        if let directory = directory {
            ownerContact = try copyContactMedia(for: ownerContact, from: iPhoneBackup, to: directory)
        }
        contacts.append(ownerContact)

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
                let memberIds = try GroupMember.fetchGroupMemberIds(forChatId: chatInfo.id, from: db)
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

        return contacts
    }
    
    /// Copies contact media files if available.
    private func copyContactMedia(for contact: ContactInfo, from iPhoneBackup: IPhoneBackup, to directory: URL?) throws -> ContactInfo {
        var updated = contact
        let prefix = "Media/Profile/\(contact.phone)"
        let files  = iPhoneBackup.fetchWAFileDetails(contains: prefix)

        let latest = getLatestFile(for: prefix, fileExtension: "jpg",   files: files) ??
                     getLatestFile(for: prefix, fileExtension: "thumb", files: files)
        if let (fileName, hash) = latest {
            let targetFileName = contact.phone + (fileName.hasSuffix(".jpg") ? ".jpg" : ".thumb")
            try mediaCopier?.copy(hash: hash,
                                  named: targetFileName,
                                  to: directory)
            updated.photoFilename = targetFileName
        }
        return updated
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

// MARK: - String Extension

extension String {
    /// Extracts the phone number from a JID string.
    var extractedPhone: String {
        return self.components(separatedBy: "@").first ?? ""
    }
}

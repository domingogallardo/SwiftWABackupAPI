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
    
    init(id: Int, contactJid: String, name: String, 
         numberMessages: Int, lastMessageDate: Date) {
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

enum SupportedMessageType: Int64, CaseIterable {
    case text = 0
    case image = 1
    case video = 2
    case audio = 3
    case location = 5
    case links = 7
    case docs = 8
    case gifs = 11
    case sticker = 15

    var description: String {
        switch self {
        case .text: return "Text"
        case .image: return "Image"
        case .video: return "Video"
        case .audio: return "Audio"
        case .location: return "Location"
        case .links: return "Link"
        case .docs: return "Document"
        case .gifs: return "GIF"
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

public struct ProfileInfo: CustomStringConvertible, Encodable, Hashable {
    public let name: String
    public let phone: String
    public var photoFilename: String?
    public var thumbnailFilename: String?

    public var description: String {
        return "Profile: Phone - \(phone), Name - \(name)"
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

    // The function needs permission to access 
    // ~/Library/Application Support/MobileSync/Backup/
    // Go to System Preferences -> Security & Privacy -> Full Disk Access
    public func getLocalBackups() -> [IPhoneBackup] {
        return phoneBackup.getLocalBackups()
    }

    // Obtains the URL of the ChatStorage.sqlite file in a backup and
    // associates it with the backup identifier. The API can be connected to
    // more than one ChatStorage.sqlite file at the same time.
    public func connectChatStorageDb(from iPhoneBackup: IPhoneBackup) -> Bool {
        guard let chatStorageHash = iPhoneBackup.fetchWAFileHash(
                                            endsWith: "ChatStorage.sqlite") else {
            print("Error: No ChatStorage.sqlite file found in backup")
            return false
        }

        let chatStorageUrl = iPhoneBackup.getUrl(fileHash: chatStorageHash)

        guard let chatStorageDb = try? DatabaseQueue(path: chatStorageUrl.path) else {
            print("Error: Cannot connect to ChatStorage.sqlite file")
            return false
        }

        // Store the connected DatabaseQueue for future use
        chatDatabases[iPhoneBackup.identifier] = chatStorageDb
        return true
    }

    public func getChats(from iPhoneBackup: IPhoneBackup) -> [ChatInfo] {
        guard let dbQueue = chatDatabases[iPhoneBackup.identifier] else {
            print("Error: ChatStorage.sqlite database is not connected for this backup")
            return []
        }
        let chats = fetchChats(from: dbQueue)
        return chats.sorted { $0.lastMessageDate > $1.lastMessageDate }
    }

    public func getChatMessages(chatId: Int, 
                                directoryToSaveMedia directory: URL, 
                                from iPhoneBackup: IPhoneBackup) -> [MessageInfo] {
        guard let dbQueue = chatDatabases[iPhoneBackup.identifier] else {
            print("Error: ChatStorage.sqlite database is not connected for this backup")
            return []
        }
        guard let chatInfo = fetchChatInfo(id: chatId, from: dbQueue) else {
            print("Error: Chat with id \(chatId) not found")
            return []
        }
        let messages = fetchChatMessages(chatId: chatId, type: chatInfo.chatType, 
                                         directoryToSaveMedia: directory, 
                                         iPhoneBackup: iPhoneBackup, from: dbQueue)
        return messages.sorted { $0.date > $1.date }
    }

    public func getProfiles(directoryToSaveMedia directory: URL, 
                            from iPhoneBackup: IPhoneBackup) -> [ProfileInfo] {
        guard let dbQueue = chatDatabases[iPhoneBackup.identifier] else {
            print("Error: ChatStorage.sqlite database is not connected for this backup")
            return []
        }

        let chats = fetchChats(from: dbQueue)
        let profilesSet = extractProfiles(from: chats, using: dbQueue)
        
        return profilesSet.map { profile in
            return copyProfileMedia(for: profile, from: iPhoneBackup, to: directory)
        }.sorted { $0.name < $1.name }
    }

    public func getUserProfile(directoryToSaveMedia directory: URL, 
                             from iPhoneBackup: IPhoneBackup) -> ProfileInfo? {
        guard let dbQueue = chatDatabases[iPhoneBackup.identifier] else {
            print("Error: ChatStorage.sqlite database is not connected for this backup")
            return nil
        }
        var userProfile = fetchUserProfile(from: dbQueue)
        let userPhotoTargetUrl = directory.appendingPathComponent("Photo.jpg")
        let userThumbnailTargetUrl = directory.appendingPathComponent("Photo.thumb")
        if let userPhotoHash = iPhoneBackup.fetchWAFileHash(
            endsWith: "Media/Profile/Photo.jpg") {
            do {
                try copy(hashFile: userPhotoHash, 
                         toTargetFileUrl: userPhotoTargetUrl, 
                         from: iPhoneBackup)

                // Inform the delegate that a media file has been written
                delegate?.didWriteMediaFile(fileName: userPhotoTargetUrl.path)

                userProfile.photoFilename = "Photo.jpg"
            } catch {
                print("Error: Cannot copy user photo file to "
                      + "\(userPhotoTargetUrl.path)")
            }
        }
        if let userThumbnailHash = iPhoneBackup.fetchWAFileHash(
            endsWith: "Media/Profile/Photo.thumb") {
            do {
                try copy(hashFile: userThumbnailHash, 
                         toTargetFileUrl: userThumbnailTargetUrl, 
                         from: iPhoneBackup)

                // Inform the delegate that a media file has been written
                delegate?.didWriteMediaFile(fileName: userThumbnailTargetUrl.path)

                userProfile.thumbnailFilename = "Photo.thumb"
            } catch {
                print("Error: Cannot copy user photo file to "
                      + "\(userPhotoTargetUrl.path)")
            }
        }
        return userProfile
    } 

    // Private functions

    private func extractProfiles(from chats: [ChatInfo], 
                                 using dbQueue: DatabaseQueue) -> Set<ProfileInfo> {
        var profilesSet: Set<ProfileInfo> = []
        for chat in chats {
            let profile = ProfileInfo(name: chat.name, 
                                      phone: chat.contactJid.extractedPhone)
            profilesSet.insert(profile)
            if chat.chatType == .group {
                    let groupProfiles = fetchGroupMembersProfiles(chatId: chat.id, 
                                                                  from: dbQueue)
                    profilesSet.formUnion(groupProfiles)
            }
        }
        return profilesSet
    }

    private func copyProfileMedia(for profile: ProfileInfo, 
                                  from iPhoneBackup: IPhoneBackup, 
                                  to directory: URL) -> ProfileInfo {
        var updatedProfile = profile
        let profilePhotoFilename = "Media/Profile/\(profile.phone)"
        let filesNamesAndHashes = 
            iPhoneBackup.fetchWAFileDetails(contains: profilePhotoFilename)
        
        if let latestFile = getLatestFile(for: profilePhotoFilename, 
                                          fileExtension: "jpg", 
                                          files: filesNamesAndHashes) {
            let targetFilename = profile.phone + ".jpg"
            do {
                let targetFileUrl = directory.appendingPathComponent(targetFilename)
                try copy(hashFile: latestFile.fileHash, 
                         toTargetFileUrl: targetFileUrl, 
                         from: iPhoneBackup)

                // Inform the delegate that a media file has been written
                delegate?.didWriteMediaFile(fileName: targetFileUrl.path)

                updatedProfile.photoFilename = targetFilename
            } catch {
                print("Error: Cannot copy photo file to " + 
                      "\(directory.appendingPathComponent(targetFilename).path)")
            }
        }
        if let latestFile = getLatestFile(for: profilePhotoFilename, 
                                          fileExtension: "thumb", 
                                          files: filesNamesAndHashes) {
            let targetFilename = profile.phone + ".thumb"
            do {
                let targetFileUrl = directory.appendingPathComponent(targetFilename)
                try copy(hashFile: latestFile.fileHash, 
                         toTargetFileUrl: targetFileUrl, 
                         from: iPhoneBackup)

                // Inform the delegate that a media file has been written
                delegate?.didWriteMediaFile(fileName: targetFileUrl.path)

                updatedProfile.thumbnailFilename = targetFilename
            } catch {
                print("Error: Cannot copy photo file to " + 
                      "\(directory.appendingPathComponent(targetFilename).path)")
            }
        }
        return updatedProfile
    }

    private func copy(hashFile: String, 
                      toTargetFileUrl url: URL, 
                      from iPhoneBackup: IPhoneBackup) throws {
        let sourceFileUrl = iPhoneBackup.getUrl(fileHash: hashFile) 
        try FileManager.default.copyItem(at: sourceFileUrl, to: url)
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

    private func fetchUserProfile(from dbQueue: DatabaseQueue) -> ProfileInfo {
        var profilePhone = ""
        
        // Fetch user phone number
        do {
            try dbQueue.read { db in
                // Fetch one row from ZWAMESSAGE table where ZMESSAGETYPE = 6 or 10, 
                // user phone number is in ZTOJID
                let userProfileRow = try Row.fetchOne(db, sql: """
                SELECT ZTOJID FROM ZWAMESSAGE WHERE ZMESSAGETYPE IN (6, 10)
                """)
                if let userPhone = userProfileRow?["ZTOJID"] as? String {
                    profilePhone = userPhone.extractedPhone
                }
            }
        } catch {
            print("Error: \(error)")
        }

        return ProfileInfo(name: "Me", phone: profilePhone)
    }

    // Fetch the profile info of the participants of a gruop chat
    private func fetchGroupMembersProfiles(chatId: Int, 
                                           from dbQueue: DatabaseQueue) -> Set<ProfileInfo> {
        var groupMembers: [Int64] = []
        var profilesSet: Set<ProfileInfo> = []
        do {
            try dbQueue.read { db in
                // Fetch the distinct members of the messages in the group chat

                // Prepare the IN clause for the SQL query using the supported message types
                let supportedMessageTypes = SupportedMessageType.allValues
                    .map { "\($0)" }
                    .joined(separator: ", ")

                // Fetch the distinct members of the messages in the group chat of 
                // supported message types
                let groupMembersRows = try Row.fetchAll(db, sql: """
                SELECT DISTINCT ZGROUPMEMBER FROM ZWAMESSAGE WHERE ZCHATSESSION = ? 
                AND ZMESSAGETYPE IN (\(supportedMessageTypes))
                """, arguments: [chatId])
                for memberRow in groupMembersRows {
                    if let memberId = memberRow["ZGROUPMEMBER"] as? Int64 {
                        groupMembers.append(memberId)
                    }
                }
                for memberId in groupMembers {
                    let (senderName, senderPhone) = 
                        try fetchSenderInfo(groupMemberId: memberId, from: db)
                    let profile = ProfileInfo(name: senderName ?? "", 
                                              phone: senderPhone ?? "")
                    profilesSet.insert(profile)
                }
            }
        } catch {
            print("Error: \(error)")
        }
        return profilesSet
    }

    private func fetchChats(from dbQueue: DatabaseQueue) -> [ChatInfo] {
        var chatInfos: [ChatInfo] = []
        do {
            try dbQueue.read { db in
                // Chats ending with "status" are not real chats
                let chatSessions = try Row.fetchAll(db, sql: """
                SELECT Z_PK, ZCONTACTJID, ZPARTNERNAME, ZLASTMESSAGEDATE 
                FROM ZWACHATSESSION WHERE ZCONTACTJID NOT LIKE ?
                """, arguments: ["%@status"])
                for chatRow in chatSessions {
                    let chatId = chatRow["Z_PK"] as? Int64 ?? 0
                    let contactJid = chatRow["ZCONTACTJID"] as? String ?? "Unknown"
                    let chatName = chatRow["ZPARTNERNAME"] as? String ?? "Unknown"
                    let lastMessageDate = convertTimestampToDate(
                        timestamp: chatRow["ZLASTMESSAGEDATE"] as Any)
                    let numberChatMessages = 
                        try Int.fetchOne(db, sql: """
                            SELECT COUNT(*) FROM ZWAMESSAGE WHERE ZCHATSESSION = ?
                            """, arguments: [chatId]) ?? 0
                    // Chats with just one message are not real chats
                    if numberChatMessages > 1 {
                        let chatInfo = ChatInfo(id: Int(chatId), 
                                                contactJid: contactJid, 
                                                name: chatName, 
                                                numberMessages: numberChatMessages, 
                                                lastMessageDate: lastMessageDate)
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
                    SELECT Z_PK, ZCONTACTJID, ZPARTNERNAME, 
                    ZMESSAGECOUNTER, ZLASTMESSAGEDATE
                    FROM ZWACHATSESSION
                    WHERE Z_PK = ?
                    """, arguments: [id]) {

                    let chatId = chatRow["Z_PK"] as? Int ?? 0
                    let name = chatRow["ZPARTNERNAME"] as? String ?? ""
                    let contactJid = chatRow["ZCONTACTJID"] as? String ?? ""
                    let numberMessages = chatRow["ZMESSAGECOUNTER"] as? Int ?? 0
                    let lastMessageDate = convertTimestampToDate(
                        timestamp: chatRow["ZLASTMESSAGEDATE"] as Any)
                    
                    chatInfo = ChatInfo(id: chatId, contactJid: 
                                        contactJid, name: name, 
                                        numberMessages: numberMessages, 
                                        lastMessageDate: lastMessageDate)
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

    private func fetchChatMessages(chatId: Int, 
                                   type: ChatInfo.ChatType, 
                                   directoryToSaveMedia: URL, 
                                   iPhoneBackup: IPhoneBackup, 
                                   from dbQueue: DatabaseQueue) -> [MessageInfo] {
        var messages: [MessageInfo] = []
        
        do {
            try dbQueue.read { db in
                var chatPartnerName: String? = nil
                var chatPartnerPhone: String? = nil

                if (type == .individual) {
                    (chatPartnerName, chatPartnerPhone) = 
                    try fetchSenderInfo(fromChatSession: chatId, from: db)
                }

                // Prepare the IN clause using the supported message types
                let supportedMessageTypes = SupportedMessageType.allValues
                    .map { "\($0)" }
                    .joined(separator: ", ")

                let chatMessages = try Row.fetchAll(db, sql: """
                    SELECT Z_PK, ZTEXT, ZMESSAGEDATE, 
                        ZGROUPMEMBER, ZFROMJID, ZMEDIAITEM, 
                        ZISFROMME, ZGROUPEVENTTYPE, ZMESSAGETYPE
                    FROM ZWAMESSAGE
                    WHERE ZCHATSESSION = ? AND ZMESSAGETYPE IN (\(supportedMessageTypes))
                    """, arguments: [chatId])
                
                for messageRow in chatMessages {
                    let messageId = messageRow["Z_PK"] as? Int64 ?? 0
                    let messageText = messageRow["ZTEXT"] as? String
                    let messageDate = convertTimestampToDate(
                        timestamp: messageRow["ZMESSAGEDATE"] as Any)
                    let isFromMe = messageRow["ZISFROMME"] as? Int64 == 1
                    let messageType = messageRow["ZMESSAGETYPE"] as? Int64 ?? 0

                    guard let messageTypeStr = getMessageType(code: Int(messageType)) else {
                        // Skip not supported message types
                        continue
                    }

                    var messageInfo = MessageInfo(id: Int(messageId), 
                                                  chatId: chatId, 
                                                  message: messageText, 
                                                  date: messageDate, 
                                                  isFromMe: isFromMe,
                                                  messageType: messageTypeStr)

                    if !isFromMe {

                        // obtain the sender name and phone number

                        switch type {
                            case .group:
                                if let groupMemberId = messageRow["ZGROUPMEMBER"] as? Int64 {
                                    let (senderName, senderPhone) = 
                                        try fetchSenderInfo(groupMemberId: groupMemberId, 
                                                            from: db)
                                    messageInfo.senderName = senderName
                                    messageInfo.senderPhone = senderPhone
                                }
                                
                            case .individual:
                                messageInfo.senderName = chatPartnerName
                                messageInfo.senderPhone = chatPartnerPhone
                        }
                    }

                    // if it is a reply update the id of the message that is 
                    // replying to

                    if let mediaItemId = messageRow["ZMEDIAITEM"] as? Int64 {
                        if let replyMessageId = 
                            try fetchReplyMessageId(mediaItemId: mediaItemId, 
                                                    from: db) {
                            messageInfo.replyTo = Int(replyMessageId)
                        }
                    }

                    // if it has a media file, extract it, the thumbnail and 
                    // the caption

                    if let mediaItemId = messageRow["ZMEDIAITEM"] as? Int64 {
                        if let mediaFilename = 
                           try fetchMediaFilename(forMediaItem: mediaItemId, 
                                                  from: iPhoneBackup, 
                                                  toDirectory: directoryToSaveMedia, 
                                                  from: db) {
                            
                            switch mediaFilename {
                                case .fileName(let fileName):
                                    messageInfo.mediaFilename = fileName
                                case .error(let error):
                                    messageInfo.error = error
                            }

                            // call the delegate function after the media file is written
                            if let mediaFilename = messageInfo.mediaFilename {
                                delegate?.didWriteMediaFile(fileName: mediaFilename)
                            }

                            if let caption = try fetchCaption(mediaItemId: mediaItemId, 
                                                              from: db) {
                                messageInfo.caption = caption
                            }

                        }
                    }

                    // extract the reactions

                    messageInfo.reactions = try fetchReactions(forMessageId: messageInfo.id, 
                                                               from: db)

                    // we've done with this message, add it to the list

                    messages.append(messageInfo)
                }
            }
            return messages
        } catch {
            print("Error: \(error)")
            return []
        }
    }

    private func getMessageType(code: Int) -> String? {
        return SupportedMessageType(rawValue: Int64(code))?.description
    }

    typealias SenderInfo = (senderName: String?, senderPhone: String?)
    
    // Fetches the sender's name (ZPARTNERNAME) and phone (ZCONTACTJID) 
    // from a chat session ID. Used for individual chats.
    private func fetchSenderInfo(fromChatSession chatId: Int, 
                                 from db: Database) throws -> SenderInfo {
        if let sessionRow = try Row.fetchOne(db, sql: """
            SELECT ZCONTACTJID, ZPARTNERNAME FROM ZWACHATSESSION WHERE Z_PK = ?
            """, arguments: [chatId]) {
            let senderPhone = (sessionRow["ZCONTACTJID"] as? String)?.extractedPhone
            let senderName = sessionRow["ZPARTNERNAME"] as? String
            return (senderName, senderPhone)
        }
        return (nil, nil)
    }

    // Fetches the sender's name and phone from a group member ID. 
    // Used for group chats.
    private func fetchSenderInfo(groupMemberId: Int64, 
                                 from db: Database) throws -> SenderInfo {
        if let memberRow = try Row.fetchOne(db, sql: """
            SELECT ZMEMBERJID, ZCONTACTNAME FROM ZWAGROUPMEMBER WHERE Z_PK = ?
            """, arguments: [groupMemberId]),
            let memberJid = memberRow["ZMEMBERJID"] as? String {
            return obtainSenderInfo(jid: memberJid, 
                                    contactNameGroupMember: memberRow["ZCONTACTNAME"], 
                                    from: db)
        }
        return (nil, nil)
    }

    // Determines the sender's name using JID and, if unavailable, falls back 
    // to the group member contact name.
    private func obtainSenderInfo(jid: String, 
                                  contactNameGroupMember: String?, 
                                  from db: Database) -> SenderInfo {
        let senderPhone = jid.extractedPhone
        if let senderName = try? fetchSenderName(for: jid, from: db) {
            return (senderName, senderPhone)
        } else {
            return (contactNameGroupMember, senderPhone)
        }
    }
    
    // Fetches the sender's name using contact JID. Prioritizes chat session 
    // and then profile push name.
    private func fetchSenderName(for contactJid: String, 
                                 from db: Database) throws -> String? {
        if let name: String = try Row.fetchOne(db, sql: """
            SELECT ZPARTNERNAME FROM ZWACHATSESSION WHERE ZCONTACTJID = ?
            """, arguments: [contactJid])?["ZPARTNERNAME"] {
            return name
        } else if let name: String = try Row.fetchOne(db, sql: """
            SELECT ZPUSHNAME FROM ZWAPROFILEPUSHNAME WHERE ZJID = ?
            """, arguments: [contactJid])?["ZPUSHNAME"] {
            return "~"+name
        }
        return nil
    }

    private func fetchReplyMessageId(mediaItemId: Int64, 
                                     from db: Database) throws -> Int64? {
        let mediaItemRow = try Row.fetchOne(db, sql: """
            SELECT ZMETADATA FROM ZWAMEDIAITEM WHERE Z_PK = ?
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

    private func fetchOriginalMessageId(stanzaId: String, from db: Database) -> Int64? {
        do {
            let messageRow = try Row.fetchOne(db, sql: """
                SELECT Z_PK FROM ZWAMESSAGE WHERE ZSTANZAID = ?
                """, arguments: [stanzaId])
            return messageRow?["Z_PK"] as? Int64
        } catch {
            print("Database access error: \(error)")
            return nil
        }
    }

    private func fetchCaption(mediaItemId: Int64, from db: Database) throws -> String? {
        let mediaItemRow = try Row.fetchOne(db, sql: """
            SELECT ZTITLE FROM ZWAMEDIAITEM WHERE Z_PK = ?
            """, arguments: [mediaItemId])
        if let caption = mediaItemRow?["ZTITLE"] as? String, !caption.isEmpty {
            return caption
        }
        return nil
    }

    enum MediaFilename {
        case fileName(String)
        case error(String)
    }

    private func fetchMediaFilename(forMediaItem mediaItemId: Int64, 
                                    from iPhoneBackup: IPhoneBackup, 
                                    toDirectory directoryURL: URL, 
                                    from db: Database) throws -> MediaFilename? {
        if let mediaItemRow = try Row.fetchOne(db, sql: """
           SELECT ZMEDIALOCALPATH FROM ZWAMEDIAITEM WHERE Z_PK = ?
           """, arguments: [mediaItemId]),
           let mediaLocalPath = mediaItemRow["ZMEDIALOCALPATH"] as? String {

            guard let hashFile = iPhoneBackup.fetchWAFileHash(
                endsWith: mediaLocalPath) else {
                return MediaFilename.error("Media file not found: \(mediaLocalPath)")
            }
            let fileName = URL(fileURLWithPath: mediaLocalPath).lastPathComponent
            let targetFileUrl = directoryURL.appendingPathComponent(fileName)
            try copy(hashFile: hashFile, 
                     toTargetFileUrl: targetFileUrl, 
                     from: iPhoneBackup)             
            return MediaFilename.fileName(targetFileUrl.lastPathComponent)
        }
        return nil
    }

    private func fetchReactions(forMessageId messageId: Int, 
                                from db: Database) throws -> [Reaction]? {
        if let reactionsRow = try Row.fetchOne(db, sql: """
            SELECT ZRECEIPTINFO FROM ZWAMESSAGEINFO WHERE ZMESSAGE = ?
            """, arguments: [messageId]) {
            if let reactionsData = reactionsRow["ZRECEIPTINFO"] as? Data {
                return extractReactions(from: reactionsData)
            }
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
}

extension String {
    // Extracts phone from a JID string.
    var extractedPhone: String {
        return self.components(separatedBy: "@").first ?? ""
    }
}
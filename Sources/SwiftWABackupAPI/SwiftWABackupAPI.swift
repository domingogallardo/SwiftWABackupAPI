//
//  SwiftWABackupAPI.swift
//
//
//  Created by Domingo Gallardo on 24/05/23.
//

import Foundation
import GRDB

public struct ChatInfo: CustomStringConvertible, Encodable {
    enum ChatType: String, Codable {
        case group
        case individual
    }

    let id: Int
    let contactJid: String
    let name: String
    let numberMessages: Int
    let lastMessageDate: Date
    let chatType: ChatType
    
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

public struct MessageInfo: CustomStringConvertible, Encodable {
    let id: Int
    let sender: String
    let senderPhoneNumber: String
    let message: String
    let date: Date
    
    public var description: String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .medium
        let localDateString = dateFormatter.string(from: date)

        return "Message: ID - \(id), Sender - \(sender), Message - \(message), Date - \(localDateString)"
    }
}


struct DatabaseUtils {
    static func connectToDatabase(at path: String) -> DatabaseQueue? {
        do {
            let dbQueue = try DatabaseQueue(path: path)
            return dbQueue
        } catch {
            print("Cannot connect to db at path: \(path). Error: \(error)")
            return nil
        }
    }
}

public struct ChatDb {
    let database: DatabaseQueue
    init(database: DatabaseQueue) {
        self.database = database
    }
}

public class WABackup {

    let phoneBackup = BackupManager()
    private var chatDatabases: [String: DatabaseQueue] = [:]

    public init() {}    
    
    // This function checks if any local backups exist at the default backup path.
    public func hasLocalBackups() -> Bool {
        return phoneBackup.hasLocalBackups()
    }

    /* 
     The function needs permission to access ~/Library/Application Support/MobileSync/Backup/
     Go to System Preferences -> Security & Privacy -> Full Disk Access
    */
    public func getLocalBackups() -> [IPhoneBackup] {
        return phoneBackup.getLocalBackups()
    }

    /*
     This function obtain the URL of the ChatStorage.sqlite file in a backup and
     associates it with the backup identifier.
    */
    public func connectChatStorageDb(from iPhoneBackup: IPhoneBackup) -> Bool {
        guard let chatStorageUrl = phoneBackup.getChatStorageUrl(backupUrl: iPhoneBackup.url) else {
            print("Error: No ChatStorage.sqlite file found in backup")
            return false
        }

        guard let chatStorageDb = DatabaseUtils.connectToDatabase(at: chatStorageUrl.path) else {
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

    public func getChatMessages(id: Int, from iPhoneBackup: IPhoneBackup) -> [MessageInfo] {
        guard let db = chatDatabases[iPhoneBackup.identifier] else {
            print("Error: ChatStorage.sqlite database is not connected for this backup")
            return []
        }
        guard let chatInfo = fetchChatInfo(id: id, from: db) else {
            print("Error: Chat with id \(id) not found")
            return []
        }
        print("ChatInfo: \(chatInfo)")
        let messages = fetchChatMessages(id: id, type: chatInfo.chatType, from: db)
        return messages.sorted { $0.date > $1.date }
    }

    private func fetchChats(from db: DatabaseQueue) -> [ChatInfo] {
        var chatInfos: [ChatInfo] = []
        do {
            try db.read { db in
                // Chats ending with "status" are not real chats
                let chatSessions = try Row.fetchAll(db, sql: "SELECT * FROM ZWACHATSESSION WHERE ZCONTACTJID NOT LIKE ?", arguments: ["%@status"])
                for session in chatSessions {
                    let chatId = session["Z_PK"] as? Int64 ?? 0
                    let contactJid = session["ZCONTACTJID"] as? String ?? "Unknown"
                    let chatName = session["ZPARTNERNAME"] as? String ?? "Unknown"
                    let lastMessageDate = convertTimestampToDate(timestamp: session["ZLASTMESSAGEDATE"] as Any)
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
                if let row = try Row.fetchOne(db, sql: """
                    SELECT Z_PK, ZCONTACTJID, ZPARTNERNAME, ZMESSAGECOUNTER, ZLASTMESSAGEDATE
                    FROM ZWACHATSESSION
                    WHERE Z_PK = ?
                    """, arguments: [id]) {

                    let chatId = row["Z_PK"] as? Int ?? 0
                    let name = row["ZPARTNERNAME"] as? String ?? ""
                    let contactJid = row["ZCONTACTJID"] as? String ?? ""
                    let numberMessages = row["ZMESSAGECOUNTER"] as? Int ?? 0
                    let lastMessageDate = convertTimestampToDate(timestamp: row["ZLASTMESSAGEDATE"] as Any)
                    
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


    private func fetchChatMessages(id: Int, type: ChatInfo.ChatType, from dbQueue: DatabaseQueue) -> [MessageInfo] {
        var messages: [MessageInfo] = []
        do {
            try dbQueue.read { db in
                let chatMessages = try fetchChatMessage(chatId: id, from: db)
                
                for chatMessage in chatMessages {
                    let messageId = chatMessage["Z_PK"] as? Int64 ?? 0
                    let messageText = chatMessage["ZTEXT"] as? String ?? ""
                    let messageDate = convertTimestampToDate(timestamp: chatMessage["ZMESSAGEDATE"] as Any)
                    var senderName = "Me"
                    var senderPhoneNumber = ""

                    // obtain the sender name
                    switch type {
                        case .group:
                            let groupMemberId = chatMessage["ZGROUPMEMBER"] as? Int64    
                            if let groupMemberId = groupMemberId {
                                (senderName, senderPhoneNumber) = try fetchSenderName(groupMemberId: groupMemberId, from: db)
                            }
                        case .individual:
                            let fromJid = chatMessage["ZFROMJID"] as? String
                            if let fromJid = fromJid {
                                (senderName, senderPhoneNumber) = try fetchSenderName(fromJid: fromJid, from: db)
                            }
                    }
                    let messageInfo = MessageInfo(id: Int(messageId), sender: senderName, senderPhoneNumber: senderPhoneNumber, 
                                                message: messageText, date: messageDate)
                    messages.append(messageInfo)
                }
            }
            return messages
        } catch {
            print("Database access error: \(error)")
            return []
        }
    }

    private func fetchChatMessage(chatId: Int, from db: Database) throws -> [Row] {
        let chatMessages = try Row.fetchAll(db, sql: """
            SELECT ZWAMESSAGE.Z_PK, ZWAMESSAGE.ZTEXT, ZWAMESSAGE.ZMESSAGEDATE, ZWAMESSAGE.ZGROUPMEMBER, ZWAMESSAGE.ZFROMJID
            FROM ZWAMESSAGE
            WHERE ZWAMESSAGE.ZCHATSESSION = ?
            """, arguments: [chatId])
        return chatMessages
    }

    typealias SenderInfo = (senderName: String, senderPhoneNumber: String)

    private func fetchSenderName(groupMemberId: Int64, from db: Database) throws -> SenderInfo {
        var senderPhoneNumber: String = ""

        let memberJid: String? = try Row.fetchOne(db, sql: """
            SELECT ZMEMBERJID FROM ZWAGROUPMEMBER WHERE Z_PK = ?
            """, arguments: [groupMemberId])?["ZMEMBERJID"]
            
        senderPhoneNumber = memberJid?.components(separatedBy: "@").first ?? ""
        
        let partnerName: String? = try Row.fetchOne(db, sql: """
            SELECT ZPARTNERNAME FROM ZWACHATSESSION WHERE ZCONTACTJID = ?
            """, arguments: [memberJid ?? ""])?["ZPARTNERNAME"]

        return (partnerName ?? "Me", senderPhoneNumber)
    }

    private func fetchSenderName(fromJid: String, from db: Database) throws -> SenderInfo {
        let senderPhoneNumber = fromJid.components(separatedBy: "@").first ?? ""
        
        let partnerName: String? = try Row.fetchOne(db, sql: """
            SELECT ZPARTNERNAME FROM ZWACHATSESSION WHERE ZCONTACTJID = ?
            """, arguments: [fromJid])?["ZPARTNERNAME"]

        return (partnerName ?? "Me", senderPhoneNumber)
    }

    private func convertTimestampToDate(timestamp: Any) -> Date {
        if let timestamp = timestamp as? Double {
            return Date(timeIntervalSinceReferenceDate: timestamp)
        } else if let timestamp = timestamp as? Int64 {
            return Date(timeIntervalSinceReferenceDate: Double(timestamp))
        }
        return Date(timeIntervalSinceReferenceDate: 0)
    }
}

//
//  WABackup+Chats.swift
//  SwiftWABackupAPI
//

import Foundation
import GRDB

public extension WABackup {
    /// Retrieves all supported chats from the connected WhatsApp database.
    func getChats(directoryToSavePhotos directory: URL? = nil) throws -> [ChatInfo] {
        guard let dbQueue = chatDatabase, let iPhoneBackup = iPhoneBackup else {
            throw DatabaseErrorWA.connection(DatabaseError(message: "Database not connected"))
        }

        let chatInfos = try dbQueue.performRead { db -> [ChatInfo] in
            let chatSessions = try ChatSession.fetchAllChats(from: db)

            return try chatSessions.compactMap { chatSession -> ChatInfo? in
                guard chatSession.sessionType != 5 else {
                    return nil
                }

                let chatName = resolvedChatName(for: chatSession)
                let photoFilename: String?

                if let directory {
                    photoFilename = try fetchChatPhotoFilename(
                        for: chatSession.contactJid,
                        chatId: Int(chatSession.id),
                        to: directory,
                        from: iPhoneBackup
                    )
                } else {
                    photoFilename = nil
                }

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
}

extension WABackup {
    func resolvedChatName(for chatSession: ChatSession) -> String {
        if let ownerJid, chatSession.contactJid == ownerJid {
            return "Me"
        }

        return chatSession.partnerName
    }

    func sortChatsByDate(_ chats: [ChatInfo]) -> [ChatInfo] {
        chats.sorted { $0.lastMessageDate > $1.lastMessageDate }
    }

    func fetchChatPhotoFilename(
        for contactJid: String,
        chatId: Int,
        to directory: URL,
        from backup: IPhoneBackup
    ) throws -> String? {
        let basePath: String

        if contactJid.isIndividualJid {
            basePath = "Media/Profile/\(contactJid.extractedPhone)"
        } else if contactJid.isGroupJid {
            let groupId = contactJid.components(separatedBy: "@").first ?? contactJid
            basePath = "Media/Profile/\(groupId)"
        } else {
            return nil
        }

        let files = backup.fetchWAFileDetails(contains: basePath)
        guard let latest = FileUtils.latestFile(for: basePath, fileExtension: "jpg", in: files)
            ?? FileUtils.latestFile(for: basePath, fileExtension: "thumb", in: files) else {
            return nil
        }

        let ext = latest.filename.hasSuffix(".jpg") ? ".jpg" : ".thumb"
        let fileName = "chat_\(chatId)\(ext)"

        try mediaCopier?.copy(hash: latest.fileHash, named: fileName, to: directory)
        return fileName
    }
}

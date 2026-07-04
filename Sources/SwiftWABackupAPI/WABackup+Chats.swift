//
//  WABackup+Chats.swift
//  SwiftWABackupAPI
//

import Foundation
import GRDB

public extension WABackup {
    /// Retrieves all supported chats from the connected WhatsApp database.
    func getChats(
        directoryToSavePhotos directory: URL? = nil,
        progress: WABackupProgressHandler? = nil
    ) throws -> [ChatInfo] {
        guard let dbQueue = chatDatabase, let whatsAppBackup else {
            throw DatabaseErrorWA.connection(DatabaseError(message: "Database not connected"))
        }

        reportProgress(
            progress,
            phase: .loadingChats,
            completedUnitCount: 0,
            unit: .chats
        )

        let chatInfos = try dbQueue.performRead { db -> [ChatInfo] in
            let chatSessions = try ChatSession.fetchAllChats(from: db)
            reportProgress(
                progress,
                phase: .loadingChats,
                completedUnitCount: 0,
                totalUnitCount: chatSessions.count,
                unit: .chats
            )

            var chatInfos: [ChatInfo] = []
            chatInfos.reserveCapacity(chatSessions.count)

            for (index, chatSession) in chatSessions.enumerated() {
                let completed = index + 1
                let currentItem = chatSession.contactJid

                guard chatSession.sessionType != 5 else {
                    reportProgress(
                        progress,
                        phase: .loadingChats,
                        completedUnitCount: completed,
                        totalUnitCount: chatSessions.count,
                        unit: .chats,
                        currentItem: currentItem
                    )
                    continue
                }

                let chatName = resolvedChatName(for: chatSession)
                let photoFilename: String?
                if let directory {
                    photoFilename = try fetchChatPhotoFilename(
                        for: chatSession.contactJid,
                        chatId: Int(chatSession.id),
                        to: directory,
                        from: whatsAppBackup,
                        progress: progress
                    )
                } else {
                    photoFilename = nil
                }

                chatInfos.append(ChatInfo(
                    id: Int(chatSession.id),
                    contactJid: chatSession.contactJid,
                    name: chatName,
                    numberMessages: Int(chatSession.messageCounter),
                    lastMessageDate: chatSession.lastMessageDate,
                    isArchived: chatSession.isArchived,
                    photoFilename: photoFilename
                ))

                reportProgress(
                    progress,
                    phase: .loadingChats,
                    completedUnitCount: completed,
                    totalUnitCount: chatSessions.count,
                    unit: .chats,
                    currentItem: chatName
                )
            }

            return chatInfos
        }

        let sortedChats = sortChatsByDate(chatInfos)
        reportProgress(
            progress,
            phase: .completed,
            completedUnitCount: 1,
            totalUnitCount: 1,
            unit: .phases,
            currentItem: "getChats"
        )
        return sortedChats
    }
}

extension WABackup {
    func resolvedChatName(for chatSession: ChatSession) -> String {
        if let ownerJid, chatSession.contactJid == ownerJid {
            return "Me"
        }

        return chatSession.partnerName.normalizedWhatsAppDisplayText
    }

    func sortChatsByDate(_ chats: [ChatInfo]) -> [ChatInfo] {
        chats.sorted { $0.lastMessageDate > $1.lastMessageDate }
    }

    func fetchChatPhotoFilename(
        for contactJid: String,
        chatId: Int,
        to directory: URL,
        from whatsAppBackup: ExtractedWhatsAppBackup,
        progress: WABackupProgressHandler? = nil
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

        let files = try whatsAppBackup.fileDetails(containing: basePath)
        guard let latest = FileUtils.latestFile(for: basePath, fileExtension: "jpg", in: files)
            ?? FileUtils.latestFile(for: basePath, fileExtension: "thumb", in: files) else {
            return nil
        }

        let ext = latest.filename.hasSuffix(".jpg") ? ".jpg" : ".thumb"
        let fileName = "chat_\(chatId)\(ext)"

        try mediaCopier?.copy(sourceURL: latest.sourceURL, named: fileName, to: directory, progress: progress)
        return fileName
    }
}

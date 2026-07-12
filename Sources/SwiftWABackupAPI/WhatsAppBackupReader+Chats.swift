//
//  WhatsAppBackupReader+Chats.swift
//  SwiftWABackupAPI
//

import Foundation
import GRDB

public extension WhatsAppBackupReader {
    /// Retrieves all supported chats from the connected WhatsApp database.
    ///
    /// If `directory` is omitted and the reader has an `exportRootDirectory`,
    /// profile photos are copied to its `ChatProfilePhotos` subdirectory.
    func getChats(
        directoryToSavePhotos directory: URL? = nil,
        progress: WABackupProgressHandler? = nil
    ) throws -> [ChatInfo] {
        let profilePhotosDirectory = try chatProfilePhotosDirectory(override: directory)
        let profileFiles = try whatsAppBackup.allProfileFileDetails()
        reportProgress(
            progress,
            phase: .loadingChats,
            completedUnitCount: 0,
            unit: .chats
        )

        let chatInfos = try chatDatabase.performRead { db -> [ChatInfo] in
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
                let photo = try fetchChatPhoto(
                    for: chatSession.contactJid,
                    chatId: Int(chatSession.id),
                    from: profileFiles,
                    to: profilePhotosDirectory,
                    in: whatsAppBackup,
                    progress: progress
                )

                chatInfos.append(ChatInfo(
                    id: Int(chatSession.id),
                    contactJid: chatSession.contactJid,
                    name: chatName,
                    numberMessages: Int(chatSession.messageCounter),
                    lastMessageDate: chatSession.lastMessageDate,
                    isArchived: chatSession.isArchived,
                    photoFilename: photo.exportedFilename,
                    photoReference: photo.reference
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

extension WhatsAppBackupReader {
    func resolvedChatName(for chatSession: ChatSession) -> String {
        if let ownerJid, chatSession.contactJid == ownerJid {
            return "Me"
        }

        return chatSession.partnerName.normalizedWhatsAppDisplayText
    }

    func sortChatsByDate(_ chats: [ChatInfo]) -> [ChatInfo] {
        chats.sorted { $0.lastMessageDate > $1.lastMessageDate }
    }

    func fetchChatPhoto(
        for contactJid: String,
        chatId: Int,
        from profileFiles: [WhatsAppFileDetails],
        to directory: URL?,
        in whatsAppBackup: ExtractedWhatsAppBackup,
        progress: WABackupProgressHandler? = nil
    ) throws -> (exportedFilename: String?, reference: MediaReference?) {
        let basePath: String

        if contactJid.isIndividualJid {
            basePath = "Media/Profile/\(contactJid.extractedPhone)"
        } else if contactJid.isGroupJid {
            let groupId = contactJid.components(separatedBy: "@").first ?? contactJid
            basePath = "Media/Profile/\(groupId)"
        } else {
            return (nil, nil)
        }

        guard let latest = FileUtils.latestFile(for: basePath, fileExtension: "jpg", in: profileFiles)
            ?? FileUtils.latestFile(for: basePath, fileExtension: "thumb", in: profileFiles) else {
            return (nil, nil)
        }

        let reference = try whatsAppBackup.mediaReference(sourceURL: latest.sourceURL)
        let ext = latest.filename.hasSuffix(".jpg") ? ".jpg" : ".thumb"
        let fileName = "chat_\(chatId)\(ext)"

        if let directory {
            try mediaCopier.copy(
                sourceURL: latest.sourceURL,
                named: fileName,
                to: directory,
                progress: progress
            )
            return (fileName, reference)
        }

        return (nil, reference)
    }
}

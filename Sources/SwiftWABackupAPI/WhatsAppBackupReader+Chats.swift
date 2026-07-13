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
                let photoFilename: String?
                if let profilePhotosDirectory {
                    photoFilename = try fetchChatPhotoFilename(
                        for: chatSession,
                        chatId: Int(chatSession.id),
                        to: profilePhotosDirectory,
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

    func fetchChatPhotoFilename(
        for chatSession: ChatSession,
        chatId: Int,
        to directory: URL,
        from whatsAppBackup: ExtractedWhatsAppBackup,
        progress: WABackupProgressHandler? = nil
    ) throws -> String? {
        let basePaths = profilePhotoBasePaths(for: chatSession)
        guard !basePaths.isEmpty else {
            return nil
        }

        var latestMatch: (file: WhatsAppFileDetails, timestamp: Int)?

        for basePath in basePaths {
            let files = try whatsAppBackup.fileDetails(containing: basePath)
            guard let latest = FileUtils.latestFile(for: basePath, fileExtension: "jpg", in: files)
                ?? FileUtils.latestFile(for: basePath, fileExtension: "thumb", in: files) else {
                continue
            }

            let fileExtension = latest.filename.hasSuffix(".jpg") ? "jpg" : "thumb"
            let timestamp = FileUtils.extractTimeSuffix(
                from: basePath,
                fileExtension: fileExtension,
                fileName: latest.filename
            ) ?? 0

            if timestamp > (latestMatch?.timestamp ?? -1) {
                latestMatch = (latest, timestamp)
            }
        }

        guard let latest = latestMatch?.file else {
            return nil
        }

        let ext = latest.filename.hasSuffix(".jpg") ? ".jpg" : ".thumb"
        let fileName = "chat_\(chatId)\(ext)"

        try mediaCopier.copy(sourceURL: latest.sourceURL, named: fileName, to: directory, progress: progress)
        return fileName
    }

    private func profilePhotoBasePaths(for chatSession: ChatSession) -> [String] {
        if chatSession.contactJid.isGroupJid {
            return ["Media/Profile/\(chatSession.contactJid.jidUser)"]
        }

        guard chatSession.contactJid.isIndividualJid || chatSession.contactJid.isLidJid else {
            return []
        }

        let addressBookContact = addressBookIndex?.contact(for: chatSession.contactJid)
        let identifiers = [
            chatSession.contactJid.jidUser,
            chatSession.contactIdentifier?.jidUser,
            addressBookContact?.lid?.jidUser,
            addressBookContact?.whatsAppID?.jidUser
        ]

        var seen = Set<String>()
        return identifiers.compactMap { identifier in
            guard let identifier, !identifier.isEmpty, seen.insert(identifier).inserted else {
                return nil
            }
            return "Media/Profile/\(identifier)"
        }
    }
}

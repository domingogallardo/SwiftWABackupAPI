//
//  WhatsAppBackupReader+ChatExports.swift
//  SwiftWABackupAPI
//

import Foundation

public extension WhatsAppBackupReader {
    /// Creates a self-contained chat export with `chat.json` and copied media.
    ///
    /// The export is assembled in a temporary sibling directory and moved into
    /// `Chats/<chatId>` only after the document and copied files validate.
    func exportChat(
        chatId: Int,
        overwriteExisting: Bool = false,
        progress: WABackupProgressHandler? = nil
    ) throws -> ExportedChat {
        let finalLayout = try chatExportLayout(chatId: chatId)
        let fileManager = FileManager.default

        try performExportFileOperation(at: finalLayout.chatsDirectoryURL) {
            try fileManager.createDirectory(
                at: finalLayout.chatsDirectoryURL,
                withIntermediateDirectories: true
            )
        }

        if fileManager.fileExists(atPath: finalLayout.directoryURL.path),
           !overwriteExisting {
            throw ChatExportError.alreadyExists(
                chatId: chatId,
                directory: finalLayout.directoryURL
            )
        }

        let temporaryLayout = finalLayout.temporarySibling()
        defer {
            if fileManager.fileExists(atPath: temporaryLayout.directoryURL.path) {
                try? fileManager.removeItem(at: temporaryLayout.directoryURL)
            }
        }

        try performExportFileOperation(at: temporaryLayout.mediaDirectoryURL) {
            try fileManager.createDirectory(
                at: temporaryLayout.mediaDirectoryURL,
                withIntermediateDirectories: true
            )
        }

        let chatPayload = try getChat(
            chatId: chatId,
            directoryToSaveMedia: temporaryLayout.mediaDirectoryURL,
            progress: progress
        )
        var chatInfo = chatPayload.chatInfo
        chatInfo.photoFilename = try exportedChatPhotoFilename(
            for: chatPayload,
            mediaDirectory: temporaryLayout.mediaDirectoryURL,
            progress: progress
        )
        let payload = ChatDumpPayload(
            chatInfo: chatInfo,
            messages: chatPayload.messages,
            contacts: chatPayload.contacts
        )
        let document = ExportedChatDocument(payload: payload)

        let documentData: Data
        do {
            documentData = try Self.chatExportJSONEncoder().encode(document)
        } catch {
            throw ChatExportError.invalidDocument(
                url: temporaryLayout.documentURL,
                reason: error.localizedDescription
            )
        }

        try performExportFileOperation(at: temporaryLayout.documentURL) {
            try documentData.write(to: temporaryLayout.documentURL, options: .atomic)
        }

        try ChatExportStore.validate(
            document: document,
            documentURL: temporaryLayout.documentURL,
            mediaDirectoryURL: temporaryLayout.mediaDirectoryURL
        )
        try installExport(
            from: temporaryLayout.directoryURL,
            to: finalLayout.directoryURL,
            overwriteExisting: overwriteExisting
        )

        return try openExportedChat(chatId: chatId)
    }

    /// Opens and validates a chat previously written under the configured export root.
    func openExportedChat(chatId: Int) throws -> ExportedChat {
        try chatExportStore().openChat(chatId: chatId)
    }

    /// Returns the persistent export state for a chat from the source catalog.
    func exportState(for chat: ChatInfo) -> ChatExportState {
        guard exportRootDirectory != nil else {
            return .notExported
        }

        let layout: ChatExportLayout
        do {
            layout = try chatExportLayout(chatId: chat.id)
        } catch {
            return .invalid(reason: error.localizedDescription)
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: layout.directoryURL.path,
            isDirectory: &isDirectory
        ) else {
            return .notExported
        }

        guard isDirectory.boolValue else {
            return .invalid(reason: "The expected chat export path is not a directory.")
        }

        do {
            let exportedChat = try openExportedChat(chatId: chat.id)
            let document = exportedChat.document
            let info = ChatExportStore.info(for: exportedChat)

            if isExportStale(document: document, comparedWith: chat) {
                return .stale(info)
            }

            return .exported(info)
        } catch {
            return .invalid(reason: error.localizedDescription)
        }
    }
}

private extension WhatsAppBackupReader {
    func chatExportLayout(chatId: Int) throws -> ChatExportLayout {
        try chatExportStore().layout(chatId: chatId)
    }

    func chatExportStore() throws -> ChatExportStore {
        guard let exportRootDirectory else {
            throw ChatExportError.exportRootNotConfigured
        }
        return ChatExportStore(rootDirectory: exportRootDirectory)
    }

    static func chatExportJSONEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    func exportedChatPhotoFilename(
        for payload: ChatDumpPayload,
        mediaDirectory: URL,
        progress: WABackupProgressHandler?
    ) throws -> String? {
        switch payload.chatInfo.chatType {
        case .individual:
            let phone = payload.chatInfo.contactJid.extractedPhone
            return payload.contacts.first(where: { $0.phone == phone })?.photoFilename
        case .group:
            return try fetchChatPhotoFilename(
                for: payload.chatInfo.contactJid,
                chatId: payload.chatInfo.id,
                to: mediaDirectory,
                from: whatsAppBackup,
                progress: progress
            )
        }
    }

    func isExportStale(
        document: ExportedChatDocument,
        comparedWith chat: ChatInfo
    ) -> Bool {
        let exported = document.chat
        let dateDifference = abs(exported.lastMessageDate.timeIntervalSince(chat.lastMessageDate))

        return exported.id != chat.id
            || exported.contactJid != chat.contactJid
            || exported.name != chat.name
            || exported.numberMessages != chat.numberMessages
            || exported.chatType != chat.chatType
            || exported.isArchived != chat.isArchived
            || dateDifference >= 1
    }

    func installExport(
        from temporaryDirectory: URL,
        to finalDirectory: URL,
        overwriteExisting: Bool
    ) throws {
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: finalDirectory.path) else {
            try performExportFileOperation(at: finalDirectory) {
                try fileManager.moveItem(at: temporaryDirectory, to: finalDirectory)
            }
            return
        }

        guard overwriteExisting else {
            throw ChatExportError.alreadyExists(
                chatId: Int(finalDirectory.lastPathComponent) ?? 0,
                directory: finalDirectory
            )
        }

        try performExportFileOperation(at: finalDirectory) {
            _ = try fileManager.replaceItemAt(
                finalDirectory,
                withItemAt: temporaryDirectory,
                backupItemName: nil,
                options: []
            )
        }
    }

    func performExportFileOperation(at url: URL, operation: () throws -> Void) throws {
        do {
            try operation()
        } catch let error as ChatExportError {
            throw error
        } catch {
            throw ChatExportError.fileOperation(url: url, underlying: error)
        }
    }
}

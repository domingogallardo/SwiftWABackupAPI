//
//  ChatExportStore.swift
//  SwiftWABackupAPI
//

import Foundation

private struct ChatExportCacheSignature: Equatable {
    let documentModificationDate: Date
    let documentFileSize: Int
    let mediaDirectoryModificationDate: Date
}

private final class ChatExportCacheEntry: NSObject {
    let signature: ChatExportCacheSignature
    let exportedChat: ExportedChat

    init(signature: ChatExportCacheSignature, exportedChat: ExportedChat) {
        self.signature = signature
        self.exportedChat = exportedChat
    }
}

/// Opens and validates self-contained chat exports without requiring their source backup.
public struct ChatExportStore {
    /// Root directory whose `Chats` child contains the exported chat bundles.
    public let rootDirectory: URL

    private static let openedChatCache: NSCache<NSURL, ChatExportCacheEntry> = {
        let cache = NSCache<NSURL, ChatExportCacheEntry>()
        cache.countLimit = 6
        cache.totalCostLimit = 128 * 1_024 * 1_024
        return cache
    }()

    /// Creates a store for chat bundles below the supplied export root.
    public init(rootDirectory: URL) {
        self.rootDirectory = rootDirectory
    }

    /// Lists all valid chat exports, ordered by chat identifier.
    ///
    /// Non-chat entries below `Chats` are ignored. If a numeric chat directory
    /// contains an incomplete or invalid export, this method throws instead of
    /// silently omitting it.
    public func listExportedChats() throws -> [ChatExportInfo] {
        let chatsDirectoryURL = rootDirectory.appendingPathComponent("Chats", isDirectory: true)
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false

        guard fileManager.fileExists(atPath: chatsDirectoryURL.path, isDirectory: &isDirectory) else {
            return []
        }

        guard isDirectory.boolValue else {
            throw ChatExportError.invalidDocument(
                url: chatsDirectoryURL,
                reason: "The expected chats path is not a directory."
            )
        }

        let entries: [URL]
        do {
            entries = try fileManager.contentsOfDirectory(
                at: chatsDirectoryURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
        } catch {
            throw ChatExportError.fileOperation(url: chatsDirectoryURL, underlying: error)
        }

        let chatIds = entries.compactMap { entry -> Int? in
            guard let chatId = Int(entry.lastPathComponent),
                  entry.lastPathComponent == String(chatId) else {
                return nil
            }
            return chatId
        }.sorted()

        return try chatIds.map { chatId in
            Self.info(for: try openChat(chatId: chatId))
        }
    }

    /// Opens and validates one self-contained chat export.
    public func openChat(chatId: Int) throws -> ExportedChat {
        let layout = layout(chatId: chatId)
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false

        guard fileManager.fileExists(atPath: layout.directoryURL.path, isDirectory: &isDirectory) else {
            throw ChatExportError.notFound(chatId: chatId, directory: layout.directoryURL)
        }

        guard isDirectory.boolValue else {
            throw ChatExportError.invalidDocument(
                url: layout.directoryURL,
                reason: "The expected chat export path is not a directory."
            )
        }

        guard fileManager.fileExists(atPath: layout.documentURL.path) else {
            throw ChatExportError.notFound(chatId: chatId, directory: layout.directoryURL)
        }

        let cacheKey = layout.documentURL.standardizedFileURL as NSURL
        let initialSignature = Self.cacheSignature(for: layout)
        if let cached = Self.openedChatCache.object(forKey: cacheKey) {
            if cached.signature == initialSignature {
                return cached.exportedChat
            }
            Self.openedChatCache.removeObject(forKey: cacheKey)
        }

        let document: ExportedChatDocument
        do {
            let data = try Data(contentsOf: layout.documentURL)
            document = try Self.chatExportJSONDecoder().decode(ExportedChatDocument.self, from: data)
        } catch {
            throw ChatExportError.invalidDocument(
                url: layout.documentURL,
                reason: error.localizedDescription
            )
        }

        guard document.chat.id == chatId else {
            throw ChatExportError.invalidDocument(
                url: layout.documentURL,
                reason: "Document chat id \(document.chat.id) does not match directory chat id \(chatId)."
            )
        }

        try Self.validate(
            document: document,
            documentURL: layout.documentURL,
            mediaDirectoryURL: layout.mediaDirectoryURL
        )

        let exportedChat = ExportedChat(
            document: document,
            directoryURL: layout.directoryURL,
            documentURL: layout.documentURL,
            mediaDirectoryURL: layout.mediaDirectoryURL
        )

        if let initialSignature,
           initialSignature == Self.cacheSignature(for: layout) {
            let entry = ChatExportCacheEntry(
                signature: initialSignature,
                exportedChat: exportedChat
            )
            Self.openedChatCache.setObject(
                entry,
                forKey: cacheKey,
                cost: max(1, initialSignature.documentFileSize)
            )
        }

        return exportedChat
    }

    /// Returns whether a complete, valid export exists for the chat identifier.
    public func containsChat(chatId: Int) -> Bool {
        (try? openChat(chatId: chatId)) != nil
    }
}

extension ChatExportStore {
    func layout(chatId: Int) -> ChatExportLayout {
        ChatExportLayout(rootDirectory: rootDirectory, chatId: chatId)
    }

    static func validate(
        document: ExportedChatDocument,
        documentURL: URL,
        mediaDirectoryURL: URL
    ) throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: mediaDirectoryURL.path,
            isDirectory: &isDirectory
        ), isDirectory.boolValue else {
            throw ChatExportError.invalidDocument(
                url: documentURL,
                reason: "Media directory is missing."
            )
        }

        let chatFiles = [document.chat.photoFilename].compactMap { $0 }
        let messageFiles = document.messages.compactMap(\.mediaFilename)
        let contactFiles = document.contacts.compactMap(\.photoFilename)
        for filename in chatFiles + messageFiles + contactFiles {
            guard isSafeExportedFilename(filename) else {
                throw ChatExportError.invalidDocument(
                    url: documentURL,
                    reason: "Unsafe exported media filename: \(filename)"
                )
            }

            let fileURL = mediaDirectoryURL.appendingPathComponent(filename)
            var fileIsDirectory: ObjCBool = false
            guard FileManager.default.fileExists(
                atPath: fileURL.path,
                isDirectory: &fileIsDirectory
            ), !fileIsDirectory.boolValue else {
                throw ChatExportError.invalidDocument(
                    url: documentURL,
                    reason: "Copied media file is missing: \(filename)"
                )
            }
        }
    }

    private static func chatExportJSONDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static func isSafeExportedFilename(_ filename: String) -> Bool {
        !filename.isEmpty
            && filename == URL(fileURLWithPath: filename).lastPathComponent
            && !filename.contains("/")
            && !filename.contains("\\")
    }

    static func info(for exportedChat: ExportedChat) -> ChatExportInfo {
        let document = exportedChat.document
        return ChatExportInfo(
            chatId: document.chat.id,
            contactJid: document.chat.contactJid,
            exportedAt: document.exportedAt,
            numberMessages: document.chat.numberMessages,
            lastMessageDate: document.chat.lastMessageDate,
            schemaVersion: document.schemaVersion,
            directoryURL: exportedChat.directoryURL
        )
    }

    private static func cacheSignature(for layout: ChatExportLayout) -> ChatExportCacheSignature? {
        guard let documentValues = try? layout.documentURL.resourceValues(
            forKeys: [.contentModificationDateKey, .fileSizeKey, .isDirectoryKey]
        ), documentValues.isDirectory == false,
        let mediaValues = try? layout.mediaDirectoryURL.resourceValues(
            forKeys: [.contentModificationDateKey, .isDirectoryKey]
        ), mediaValues.isDirectory == true else {
            return nil
        }

        return ChatExportCacheSignature(
            documentModificationDate: documentValues.contentModificationDate ?? .distantPast,
            documentFileSize: documentValues.fileSize ?? 0,
            mediaDirectoryModificationDate: mediaValues.contentModificationDate ?? .distantPast
        )
    }
}

struct ChatExportLayout {
    let chatsDirectoryURL: URL
    let directoryURL: URL
    let documentURL: URL
    let mediaDirectoryURL: URL

    init(rootDirectory: URL, chatId: Int) {
        let chatsDirectoryURL = rootDirectory.appendingPathComponent("Chats", isDirectory: true)
        let directoryURL = chatsDirectoryURL.appendingPathComponent(String(chatId), isDirectory: true)

        self.chatsDirectoryURL = chatsDirectoryURL
        self.directoryURL = directoryURL
        self.documentURL = directoryURL.appendingPathComponent("chat.json")
        self.mediaDirectoryURL = directoryURL.appendingPathComponent("Media", isDirectory: true)
    }

    private init(chatsDirectoryURL: URL, directoryURL: URL) {
        self.chatsDirectoryURL = chatsDirectoryURL
        self.directoryURL = directoryURL
        self.documentURL = directoryURL.appendingPathComponent("chat.json")
        self.mediaDirectoryURL = directoryURL.appendingPathComponent("Media", isDirectory: true)
    }

    func temporarySibling() -> ChatExportLayout {
        let temporaryDirectory = chatsDirectoryURL.appendingPathComponent(
            ".exporting-\(UUID().uuidString)",
            isDirectory: true
        )
        return ChatExportLayout(
            chatsDirectoryURL: chatsDirectoryURL,
            directoryURL: temporaryDirectory
        )
    }
}

import Foundation
import ZIPFoundation
#if canImport(CryptoKit)
import CryptoKit
#endif

/// Validated portable directory. Instances can only be produced by the codec.
public struct PortableConversationDirectory {
    public let directoryURL: URL
    public let manifestURL: URL
    public let documentURL: URL
    public let mediaDirectoryURL: URL
    public let manifest: PortableConversationManifest
    public let document: PortableConversationDocument

    init(
        directoryURL: URL,
        manifest: PortableConversationManifest,
        document: PortableConversationDocument
    ) {
        self.directoryURL = directoryURL
        self.manifestURL = directoryURL.appendingPathComponent("manifest.json")
        self.documentURL = directoryURL.appendingPathComponent("chat.json")
        self.mediaDirectoryURL = directoryURL.appendingPathComponent("Media", isDirectory: true)
        self.manifest = manifest
        self.document = document
    }

    /// Adapts the validated portable document to the common composition engine.
    public func makeConversationSource(
        id: ConversationSourceID,
        perspectiveHint: ConversationPerspectiveHint? = nil
    ) throws -> ConversationSource {
        let chatID = 1
        let messageIDs = Dictionary(
            uniqueKeysWithValues: document.messages.enumerated().map {
                ($0.element.id, $0.offset + 1)
            }
        )
        let messages = document.messages.enumerated().map { index, portable in
            let author = messageAuthor(from: portable.author)
            let isFromMe = portable.author.role == .sourceUser
            var message = MessageInfo(
                id: index + 1,
                chatId: chatID,
                message: portable.text,
                date: portable.date,
                isFromMe: isFromMe,
                messageType: portable.messageType,
                author: author
            )
            message.caption = portable.caption
            message.replyTo = portable.replyTo.flatMap { messageIDs[$0] }
            message.replyToPreview = portable.replyToPreview
            message.mediaFilename = portable.mediaPath.map {
                URL(fileURLWithPath: $0).lastPathComponent
            }
            message.reactions = portable.reactions?.map {
                Reaction(emoji: $0.emoji, author: reactionAuthor(from: $0.author))
            }
            message.error = portable.warning
            message.seconds = portable.seconds
            message.latitude = portable.latitude
            message.longitude = portable.longitude
            return message
        }
        let descriptor = document.conversation
        let contactJID = try portableContactJID(descriptor)
        let mediaByteCount = Set(document.messages.compactMap(\.mediaPath)).reduce(Int64(0)) {
            partial, path in
            partial + (manifest.media.first(where: { $0.path == path })?.byteCount ?? 0)
        }
        let chat = ChatInfo(
            id: chatID,
            contactJid: contactJID,
            name: descriptor.displayName,
            numberMessages: messages.count,
            lastMessageDate: messages.last?.date ?? descriptor.exportedAt,
            isArchived: descriptor.isArchived,
            mediaByteCount: mediaByteCount,
            photoFilename: descriptor.photoPath.map {
                URL(fileURLWithPath: $0).lastPathComponent
            }
        )
        let contacts = document.contacts.compactMap { portable -> ContactInfo? in
            guard let phone = portable.identity.comparisonKeys
                .filter({ $0.hasPrefix("phone:") })
                .sorted()
                .first
                .map({ String($0.dropFirst("phone:".count)) }) else {
                return nil
            }
            return ContactInfo(
                name: portable.displayName,
                phone: phone,
                photoFilename: portable.photoPath.map {
                    URL(fileURLWithPath: $0).lastPathComponent
                }
            )
        }
        let exported = ExportedChatDocument(
            payload: ChatDumpPayload(chatInfo: chat, messages: messages, contacts: contacts),
            exportedAt: descriptor.exportedAt
        )
        let stableIDs = Dictionary(
            uniqueKeysWithValues: document.messages.enumerated().map {
                ($0.offset + 1, $0.element.id)
            }
        )
        return try ConversationSource(
            portableID: id,
            document: exported,
            mediaDirectoryURL: mediaDirectoryURL,
            conversationIdentityHint: descriptor.contactIdentity,
            perspectiveHint: perspectiveHint,
            stableMessageIDs: stableIDs
        )
    }
}

/// Creates, inspects, extracts, and opens versioned `.fmcchat` ZIP archives.
public struct PortableConversationArchiveCodec {
    public let limits: PortableArchiveLimits

    public init(limits: PortableArchiveLimits = .default) {
        self.limits = limits
    }

    public func createArchive(
        from source: ConversationSource,
        producer: PortableArchiveProducer,
        destinationURL: URL,
        overwriteExisting: Bool = false,
        progress: WABackupProgressHandler? = nil,
        cancellation: WABackupCancellationHandler? = nil
    ) throws -> PortableConversationArchiveInfo {
        try validateLimits()
        guard !producer.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !producer.version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PortableConversationArchiveError.invalidSource(
                reason: "The producer name and version are required."
            )
        }
        try portableCheckCancellation(cancellation)
        let destination = destinationURL.standardizedFileURL
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destination.path), !overwriteExisting {
            throw PortableConversationArchiveError.archiveAlreadyExists(destination)
        }
        let temporaryRoot = fileManager.temporaryDirectory.appendingPathComponent(
            "SwiftWABackupAPI-fmcchat-\(UUID().uuidString)",
            isDirectory: true
        )
        let portableDirectory = temporaryRoot.appendingPathComponent("portable", isDirectory: true)
        let temporaryArchive = destination.deletingLastPathComponent().appendingPathComponent(
            ".creating-\(UUID().uuidString).fmcchat"
        )
        var installed = false
        defer {
            try? fileManager.removeItem(at: temporaryRoot)
            if !installed {
                try? fileManager.removeItem(at: temporaryArchive)
            }
        }

        do {
            try fileManager.createDirectory(
                at: portableDirectory.appendingPathComponent("Media", isDirectory: true),
                withIntermediateDirectories: true
            )
            let built = try buildPortableDirectory(
                from: source,
                producer: producer,
                directoryURL: portableDirectory,
                progress: progress,
                cancellation: cancellation
            )
            _ = try openValidatedDirectory(at: portableDirectory)
            try portableCheckCancellation(cancellation)
            reportProgress(
                progress,
                phase: .creatingPortableConversationArchive,
                completedUnitCount: 0,
                totalUnitCount: built.archivePaths.count,
                unit: .archiveEntries
            )
            let archive = try ZIPFoundation.Archive(
                url: temporaryArchive,
                accessMode: .create
            )
            for (index, path) in built.archivePaths.enumerated() {
                try portableCheckCancellation(cancellation)
                try addFile(
                    portableDirectory.appendingPathComponent(path),
                    path: path,
                    to: archive,
                    cancellation: cancellation
                )
                reportProgress(
                    progress,
                    phase: .creatingPortableConversationArchive,
                    completedUnitCount: index + 1,
                    totalUnitCount: built.archivePaths.count,
                    unit: .archiveEntries
                )
            }
            let inspected = try inspectArchive(
                at: temporaryArchive,
                progress: progress,
                cancellation: cancellation,
                reportsCompletion: false
            )
            try installArchive(
                temporaryArchive,
                at: destination,
                overwriteExisting: overwriteExisting
            )
            installed = true
            reportProgress(
                progress,
                phase: .completed,
                completedUnitCount: 1,
                totalUnitCount: 1,
                unit: .phases
            )
            return PortableConversationArchiveInfo(
                archiveURL: destination,
                manifest: inspected.manifest,
                archiveByteCount: inspected.archiveByteCount,
                uncompressedByteCount: inspected.uncompressedByteCount,
                archiveSHA256: inspected.archiveSHA256
            )
        } catch {
            throw portableMappedError(error, url: destination)
        }
    }

    public func inspectArchive(
        at archiveURL: URL,
        progress: WABackupProgressHandler? = nil,
        cancellation: WABackupCancellationHandler? = nil
    ) throws -> PortableConversationArchiveInfo {
        try inspectArchive(
            at: archiveURL,
            progress: progress,
            cancellation: cancellation,
            reportsCompletion: true
        )
    }

    public func extractValidatedArchive(
        at archiveURL: URL,
        to destinationDirectory: URL,
        progress: WABackupProgressHandler? = nil,
        cancellation: WABackupCancellationHandler? = nil
    ) throws -> PortableConversationDirectory {
        let info = try inspectArchive(
            at: archiveURL,
            progress: progress,
            cancellation: cancellation,
            reportsCompletion: false
        )
        try portableCheckCancellation(cancellation)
        let archiveDigest = try portableSHA256File(archiveURL, cancellation: cancellation)
        guard archiveDigest == info.archiveSHA256 else {
            throw PortableConversationArchiveError.integrityMismatch(
                path: archiveURL.lastPathComponent
            )
        }
        let destination = destinationDirectory.standardizedFileURL
        let fileManager = FileManager.default
        let createdDestination = try prepareEmptyDestination(destination)
        var succeeded = false
        defer {
            if !succeeded {
                if createdDestination {
                    try? fileManager.removeItem(at: destination)
                } else {
                    try? fileManager.removeItem(
                        at: destination.appendingPathComponent("manifest.json")
                    )
                    try? fileManager.removeItem(
                        at: destination.appendingPathComponent("chat.json")
                    )
                    try? fileManager.removeItem(
                        at: destination.appendingPathComponent("Media", isDirectory: true)
                    )
                }
            }
        }

        do {
            let archive = try ZIPFoundation.Archive(url: archiveURL, accessMode: .read)
            let entries = try validatedArchiveEntries(archive)
            try fileManager.createDirectory(
                at: destination.appendingPathComponent("Media", isDirectory: true),
                withIntermediateDirectories: false
            )
            let orderedPaths = entries.keys.sorted()
            for (index, path) in orderedPaths.enumerated() {
                try portableCheckCancellation(cancellation)
                guard let entry = entries[path] else { continue }
                let outputURL = destination.appendingPathComponent(path).standardizedFileURL
                guard outputURL.path.hasPrefix(destination.path + "/") else {
                    throw PortableConversationArchiveError.unsafePath(path)
                }
                if path.hasPrefix("Media/") {
                    try extract(entry, from: archive, to: outputURL, cancellation: cancellation)
                } else {
                    try extract(entry, from: archive, to: outputURL, cancellation: cancellation)
                }
                reportProgress(
                    progress,
                    phase: .extractingPortableConversationArchive,
                    completedUnitCount: index + 1,
                    totalUnitCount: orderedPaths.count,
                    unit: .archiveEntries
                )
            }
            let directory = try openValidatedDirectory(at: destination)
            succeeded = true
            reportProgress(
                progress,
                phase: .completed,
                completedUnitCount: 1,
                totalUnitCount: 1,
                unit: .phases
            )
            return directory
        } catch {
            throw portableMappedError(error, url: archiveURL)
        }
    }

    public func openValidatedDirectory(
        at directoryURL: URL
    ) throws -> PortableConversationDirectory {
        try validateLimits()
        let directory = directoryURL.standardizedFileURL
        do {
            let files = try validatedDirectoryFiles(directory)
            guard let manifestFile = files["manifest.json"],
                  let documentFile = files["chat.json"] else {
                throw PortableConversationArchiveError.invalidDirectory(
                    directory,
                    reason: "manifest.json or chat.json is missing."
                )
            }
            guard manifestFile.byteCount <= limits.maximumJSONByteCount,
                  documentFile.byteCount <= limits.maximumJSONByteCount else {
                throw PortableConversationArchiveError.limitExceeded(
                    reason: "A JSON document is too large."
                )
            }
            let manifestData = try Data(contentsOf: manifestFile.url)
            let documentData = try Data(contentsOf: documentFile.url)
            let manifest = try portableJSONDecoder().decode(
                PortableConversationManifest.self,
                from: manifestData
            )
            let document = try portableJSONDecoder().decode(
                PortableConversationDocument.self,
                from: documentData
            )
            let actual = Dictionary(
                uniqueKeysWithValues: files.compactMap { path, file in
                    path == "manifest.json"
                        ? nil
                        : (
                            path,
                            PortableFileEntry(
                                path: path,
                                byteCount: file.byteCount,
                                sha256: file.sha256
                            )
                        )
                }
            )
            try validatePortableContent(
                manifest: manifest,
                document: document,
                actualFiles: actual
            )
            return PortableConversationDirectory(
                directoryURL: directory,
                manifest: manifest,
                document: document
            )
        } catch {
            throw portableMappedDirectoryError(error, url: directory)
        }
    }
}

private extension PortableConversationArchiveCodec {
    struct BuiltPortableDirectory {
        let archivePaths: [String]
    }

    struct RetainedPortableContact {
        let contact: ContactInfo
        let identity: CanonicalParticipantIdentity
    }

    struct ValidatedDirectoryFile {
        let url: URL
        let byteCount: Int64
        let sha256: String
    }

    struct PortableContentDigestPayload: Encodable {
        let schemaVersion: Int
        let conversation: PortableConversationDescriptor
        let document: PortableFileEntry
        let media: [PortableMediaEntry]
    }

    func inspectArchive(
        at archiveURL: URL,
        progress: WABackupProgressHandler?,
        cancellation: WABackupCancellationHandler?,
        reportsCompletion: Bool
    ) throws -> PortableConversationArchiveInfo {
        try validateLimits()
        let archiveFile = archiveURL.standardizedFileURL
        do {
            let values = try archiveFile.resourceValues(
                forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
            )
            guard values.isRegularFile == true, values.isSymbolicLink != true,
                  let fileSize = values.fileSize else {
                throw PortableConversationArchiveError.invalidArchive(
                    archiveFile,
                    reason: "The archive is not a regular file."
                )
            }
            let archiveByteCount = Int64(fileSize)
            guard archiveByteCount <= limits.maximumArchiveByteCount else {
                throw PortableConversationArchiveError.limitExceeded(
                    reason: "The ZIP is larger than the configured maximum."
                )
            }
            let archive = try ZIPFoundation.Archive(url: archiveFile, accessMode: .read)
            let entries = try validatedArchiveEntries(archive)
            guard let manifestEntry = entries["manifest.json"],
                  let documentEntry = entries["chat.json"] else {
                throw PortableConversationArchiveError.invalidArchive(
                    archiveFile,
                    reason: "manifest.json or chat.json is missing."
                )
            }
            let mediaPaths = entries.keys.filter { $0.hasPrefix("Media/") }.sorted()
            let totalEntriesToInspect = mediaPaths.count + 2
            reportProgress(
                progress,
                phase: .inspectingPortableConversationArchive,
                completedUnitCount: 0,
                totalUnitCount: totalEntriesToInspect,
                unit: .archiveEntries
            )
            let manifestData = try readData(
                manifestEntry,
                from: archive,
                maximumByteCount: limits.maximumJSONByteCount,
                cancellation: cancellation
            )
            let manifest = try portableJSONDecoder().decode(
                PortableConversationManifest.self,
                from: manifestData
            )
            reportProgress(
                progress,
                phase: .inspectingPortableConversationArchive,
                completedUnitCount: 1,
                totalUnitCount: totalEntriesToInspect,
                unit: .archiveEntries
            )
            let documentData = try readData(
                documentEntry,
                from: archive,
                maximumByteCount: limits.maximumJSONByteCount,
                cancellation: cancellation
            )
            let document = try portableJSONDecoder().decode(
                PortableConversationDocument.self,
                from: documentData
            )
            reportProgress(
                progress,
                phase: .inspectingPortableConversationArchive,
                completedUnitCount: 2,
                totalUnitCount: totalEntriesToInspect,
                unit: .archiveEntries
            )
            var actualFiles: [String: PortableFileEntry] = [
                "chat.json": PortableFileEntry(
                    path: "chat.json",
                    byteCount: Int64(documentData.count),
                    sha256: portableSHA256(documentData)
                )
            ]
            for (index, path) in mediaPaths.enumerated() {
                try portableCheckCancellation(cancellation)
                guard let entry = entries[path] else { continue }
                let hashed = try hashEntry(entry, from: archive, cancellation: cancellation)
                actualFiles[path] = PortableFileEntry(
                    path: path,
                    byteCount: hashed.byteCount,
                    sha256: hashed.sha256
                )
                reportProgress(
                    progress,
                    phase: .inspectingPortableConversationArchive,
                    completedUnitCount: index + 3,
                    totalUnitCount: totalEntriesToInspect,
                    unit: .archiveEntries
                )
            }
            try validatePortableContent(
                manifest: manifest,
                document: document,
                actualFiles: actualFiles
            )
            let uncompressedByteCount = try entries.values.reduce(Int64(0)) {
                partial, entry in
                let size = try checkedInt64(entry.uncompressedSize)
                let (sum, overflow) = partial.addingReportingOverflow(size)
                if overflow {
                    throw PortableConversationArchiveError.limitExceeded(
                        reason: "The uncompressed-size sum overflowed."
                    )
                }
                return sum
            }
            let info = PortableConversationArchiveInfo(
                archiveURL: archiveFile,
                manifest: manifest,
                archiveByteCount: archiveByteCount,
                uncompressedByteCount: uncompressedByteCount,
                archiveSHA256: try portableSHA256File(
                    archiveFile,
                    cancellation: cancellation
                )
            )
            if reportsCompletion {
                reportProgress(
                    progress,
                    phase: .completed,
                    completedUnitCount: 1,
                    totalUnitCount: 1,
                    unit: .phases
                )
            }
            return info
        } catch {
            throw portableMappedArchiveInspectionError(error, url: archiveFile)
        }
    }

    func validatedArchiveEntries(
        _ archive: ZIPFoundation.Archive
    ) throws -> [String: ZIPFoundation.Entry] {
        let entries = Array(archive)
        guard entries.count <= limits.maximumEntryCount else {
            throw PortableConversationArchiveError.limitExceeded(
                reason: "The ZIP contains too many entries."
            )
        }
        var result: [String: ZIPFoundation.Entry] = [:]
        var normalizedPaths = Set<String>()
        var total: Int64 = 0
        for entry in entries {
            let path = entry.path.precomposedStringWithCanonicalMapping
            try validatePortableArchivePath(path)
            guard entry.type == .file else {
                throw PortableConversationArchiveError.invalidArchive(
                    archive.url,
                    reason: "Only regular-file ZIP entries are allowed."
                )
            }
            let folded = path.lowercased()
            guard normalizedPaths.insert(folded).inserted, result[path] == nil else {
                throw PortableConversationArchiveError.invalidArchive(
                    archive.url,
                    reason: "The ZIP contains duplicate paths."
                )
            }
            let uncompressed = try checkedInt64(entry.uncompressedSize)
            let compressed = try checkedInt64(entry.compressedSize)
            guard uncompressed <= limits.maximumEntryByteCount else {
                throw PortableConversationArchiveError.limitExceeded(
                    reason: "An entry is larger than the configured maximum."
                )
            }
            if uncompressed > 0 {
                let ratio = Double(uncompressed) / Double(max(compressed, 1))
                guard ratio <= limits.maximumCompressionRatio else {
                    throw PortableConversationArchiveError.limitExceeded(
                        reason: "An entry exceeds the maximum compression ratio."
                    )
                }
            }
            let (newTotal, overflow) = total.addingReportingOverflow(uncompressed)
            guard !overflow, newTotal <= limits.maximumUncompressedByteCount else {
                throw PortableConversationArchiveError.limitExceeded(
                    reason: "The ZIP expands beyond the configured maximum."
                )
            }
            total = newTotal
            result[path] = entry
        }
        return result
    }

    func validatePortableArchivePath(_ path: String) throws {
        guard !path.isEmpty,
              path == path.precomposedStringWithCanonicalMapping,
              path.utf8.count <= limits.maximumPathUTF8ByteCount,
              !path.contains("\0"),
              !path.contains("\\"),
              !path.hasPrefix("/"),
              !path.hasPrefix("~"),
              !path.contains(":") else {
            throw PortableConversationArchiveError.unsafePath(path)
        }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard components.allSatisfy({
            !$0.isEmpty && $0 != "." && $0 != ".." && !$0.hasPrefix(".")
        }) else {
            throw PortableConversationArchiveError.unsafePath(path)
        }
        switch components.count {
        case 1:
            guard path == "manifest.json" || path == "chat.json" else {
                throw PortableConversationArchiveError.unsafePath(path)
            }
        case 2:
            guard components[0] == "Media",
                  isSafePortableMediaFilename(String(components[1])) else {
                throw PortableConversationArchiveError.unsafePath(path)
            }
        default:
            throw PortableConversationArchiveError.unsafePath(path)
        }
    }

    func buildPortableDirectory(
        from source: ConversationSource,
        producer: PortableArchiveProducer,
        directoryURL: URL,
        progress: WABackupProgressHandler?,
        cancellation: WABackupCancellationHandler?
    ) throws -> BuiltPortableDirectory {
        let document = source.document
        guard document.schemaVersion == ExportedChatDocument.currentSchemaVersion,
              document.chat.numberMessages == document.messages.count else {
            throw PortableConversationArchiveError.invalidSource(
                reason: "The exported document is inconsistent."
            )
        }
        let sourceMessageIDs = document.messages.map(\.id)
        guard Set(sourceMessageIDs).count == sourceMessageIDs.count else {
            throw PortableConversationArchiveError.invalidSource(
                reason: "The exported document contains duplicate message IDs."
            )
        }
        let retainedContacts = retainedPortableContacts(from: source)
        let mediaDirectory = directoryURL.appendingPathComponent("Media", isDirectory: true)
        let referencedFilenames = Set(
            [document.chat.photoFilename].compactMap { $0 }
                + document.messages.compactMap(\.mediaFilename)
                + retainedContacts.compactMap(\.contact.photoFilename)
        )
        var outputPathBySourceFilename: [String: String] = [:]
        var mediaByIdentity: [String: PortableMediaEntry] = [:]
        for (index, filename) in referencedFilenames.sorted().enumerated() {
            try portableCheckCancellation(cancellation)
            guard isSafePortableMediaFilename(filename) else {
                throw PortableConversationArchiveError.invalidSource(
                    reason: "A media filename is unsafe."
                )
            }
            let sourceURL = source.mediaDirectoryURL
                .appendingPathComponent(filename)
                .standardizedFileURL
            let values = try sourceURL.resourceValues(
                forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
            )
            guard values.isRegularFile == true, values.isSymbolicLink != true,
                  let fileSize = values.fileSize else {
                throw PortableConversationArchiveError.invalidSource(
                    reason: "A referenced media file is missing or unsafe."
                )
            }
            let byteCount = Int64(fileSize)
            guard byteCount <= limits.maximumEntryByteCount else {
                throw PortableConversationArchiveError.limitExceeded(
                    reason: "A source media file is too large."
                )
            }
            let digest = try portableSHA256File(sourceURL, cancellation: cancellation)
            let identity = "\(byteCount):\(digest)"
            if let existing = mediaByIdentity[identity] {
                outputPathBySourceFilename[filename] = existing.path
            } else {
                let outputFilename = portableMediaFilename(
                    digest: digest,
                    originalFilename: filename
                )
                let path = "Media/\(outputFilename)"
                try validatePortableArchivePath(path)
                let outputURL = mediaDirectory.appendingPathComponent(outputFilename)
                try FileManager.default.copyItem(at: sourceURL, to: outputURL)
                let entry = PortableMediaEntry(
                    path: path,
                    byteCount: byteCount,
                    sha256: digest
                )
                mediaByIdentity[identity] = entry
                outputPathBySourceFilename[filename] = path
            }
            reportProgress(
                progress,
                phase: .creatingPortableConversationArchive,
                completedUnitCount: index + 1,
                totalUnitCount: referencedFilenames.count,
                unit: .mediaFiles
            )
        }

        let descriptor = try portableDescriptor(
            from: source,
            mediaPathByFilename: outputPathBySourceFilename
        )
        let sortedMessages = document.messages.enumerated().sorted {
            if $0.element.date != $1.element.date {
                return $0.element.date < $1.element.date
            }
            return $0.offset < $1.offset
        }
        var stableIDByMessageID = source.stableMessageIDs
        for (position, item) in sortedMessages.enumerated()
        where stableIDByMessageID[item.element.id] == nil {
            stableIDByMessageID[item.element.id] = ArchiveMessageID(
                rawValue: portableDeterministicUUID(
                    seed: try portableStableMessageSeed(
                        item.element,
                        occurrence: position
                    )
                )
            )
        }
        let portableMessages = try sortedMessages.map { _, message in
            guard let stableID = stableIDByMessageID[message.id] else {
                throw PortableConversationArchiveError.invalidSource(
                    reason: "A stable message ID could not be generated."
                )
            }
            return PortableMessage(
                id: stableID,
                date: message.date,
                author: portableAuthor(
                    isFromMe: message.isFromMe,
                    author: message.author,
                    individualFallback: descriptor.contactIdentity
                ),
                messageType: message.messageType,
                text: message.message,
                caption: message.caption,
                mediaPath: message.mediaFilename.flatMap {
                    outputPathBySourceFilename[$0]
                },
                replyTo: message.replyTo.flatMap { stableIDByMessageID[$0] },
                replyToPreview: message.replyToPreview,
                reactions: message.reactions?.map {
                    PortableReaction(
                        emoji: $0.emoji,
                        author: portableAuthor(
                            isFromMe: $0.author.kind == .me,
                            author: $0.author,
                            individualFallback: descriptor.contactIdentity
                        )
                    )
                },
                warning: message.error,
                seconds: message.seconds,
                latitude: message.latitude,
                longitude: message.longitude
            )
        }.sorted(by: portableMessagePrecedes)
        let contacts = retainedContacts.map { retained in
            return PortableContact(
                identity: retained.identity,
                displayName: retained.contact.name,
                photoPath: retained.contact.photoFilename.flatMap {
                    outputPathBySourceFilename[$0]
                }
            )
        }.sorted {
            ($0.identity.preferredComparisonKey ?? "") < ($1.identity.preferredComparisonKey ?? "")
        }
        let portableDocument = PortableConversationDocument(
            conversation: descriptor,
            messages: portableMessages,
            contacts: contacts
        )
        let documentData = try portableJSONEncoder().encode(portableDocument)
        guard Int64(documentData.count) <= limits.maximumJSONByteCount else {
            throw PortableConversationArchiveError.limitExceeded(
                reason: "chat.json is too large."
            )
        }
        let documentURL = directoryURL.appendingPathComponent("chat.json")
        try documentData.write(to: documentURL, options: .atomic)
        let documentEntry = PortableFileEntry(
            path: "chat.json",
            byteCount: Int64(documentData.count),
            sha256: portableSHA256(documentData)
        )
        let media = mediaByIdentity.values.sorted { $0.path < $1.path }
        let contentDigest = try portableContentDigest(
            schemaVersion: PortableConversationManifest.currentSchemaVersion,
            conversation: descriptor,
            document: documentEntry,
            media: media
        )
        let manifest = PortableConversationManifest(
            packageID: UUID(),
            createdAt: Date(),
            producer: producer,
            implementation: PortableArchiveImplementation(
                name: "SwiftWABackupAPI",
                formatVersion: 1,
                algorithmVersion: 1
            ),
            conversation: descriptor,
            messageCount: portableMessages.count,
            firstMessageAt: portableMessages.first?.date,
            lastMessageAt: portableMessages.last?.date,
            document: documentEntry,
            media: media,
            contentDigest: contentDigest
        )
        let manifestData = try portableJSONEncoder().encode(manifest)
        guard Int64(manifestData.count) <= limits.maximumJSONByteCount else {
            throw PortableConversationArchiveError.limitExceeded(
                reason: "manifest.json is too large."
            )
        }
        try manifestData.write(
            to: directoryURL.appendingPathComponent("manifest.json"),
            options: .atomic
        )
        return BuiltPortableDirectory(
            archivePaths: ["manifest.json", "chat.json"] + media.map(\.path)
        )
    }

    func retainedPortableContacts(
        from source: ConversationSource
    ) -> [RetainedPortableContact] {
        let document = source.document
        var allowedParticipantKeys = Set<String>()
        switch document.chat.chatType {
        case .individual:
            var addresses = portableParticipantAddresses(document.chat.contactJid)
            addresses.append(contentsOf: source.conversationIdentityHint?.addresses ?? [])
            allowedParticipantKeys.formUnion(
                CanonicalParticipantIdentity(addresses: addresses).comparisonKeys
            )
        case .group:
            for message in document.messages where !message.isFromMe {
                if let author = message.author, author.kind == .participant {
                    let values = [author.phone, author.jid].compactMap { $0 }
                    let identity = CanonicalParticipantIdentity(
                        addresses: values.flatMap(portableParticipantAddresses)
                    )
                    allowedParticipantKeys.formUnion(identity.comparisonKeys)
                }
            }
            for reaction in document.messages.flatMap({ $0.reactions ?? [] })
            where reaction.author.kind == .participant {
                let values = [
                    reaction.author.phone,
                    reaction.author.jid
                ].compactMap { $0 }
                let identity = CanonicalParticipantIdentity(
                    addresses: values.flatMap(portableParticipantAddresses)
                )
                allowedParticipantKeys.formUnion(identity.comparisonKeys)
            }
        }

        var retained: [RetainedPortableContact] = []
        var retainedKeys = Set<String>()
        for contact in document.contacts {
            let identity = CanonicalParticipantIdentity(
                addresses: [ParticipantAddress(kind: .phone, value: contact.phone)]
            )
            guard !identity.addresses.isEmpty,
                  !identity.comparisonKeys.isDisjoint(with: allowedParticipantKeys),
                  let key = identity.preferredComparisonKey,
                  retainedKeys.insert(key).inserted else {
                continue
            }
            retained.append(
                RetainedPortableContact(contact: contact, identity: identity)
            )
        }
        return retained.sorted {
            let first = $0.identity.preferredComparisonKey ?? ""
            let second = $1.identity.preferredComparisonKey ?? ""
            if first != second { return first < second }
            return $0.contact.name < $1.contact.name
        }
    }

    func validatePortableContent(
        manifest: PortableConversationManifest,
        document: PortableConversationDocument,
        actualFiles: [String: PortableFileEntry]
    ) throws {
        guard manifest.schemaVersion == PortableConversationManifest.currentSchemaVersion,
              document.schemaVersion == PortableConversationDocument.currentSchemaVersion else {
            throw PortableConversationArchiveError.unsupportedSchema(
                max(manifest.schemaVersion, document.schemaVersion)
            )
        }
        guard manifest.format == PortableConversationManifest.formatIdentifier,
              manifest.implementation.name == "SwiftWABackupAPI",
              manifest.implementation.formatVersion == 1,
              manifest.implementation.algorithmVersion == 1,
              !manifest.producer.name.trimmingCharacters(
                  in: .whitespacesAndNewlines
              ).isEmpty,
              !manifest.producer.version.trimmingCharacters(
                  in: .whitespacesAndNewlines
              ).isEmpty else {
            throw PortableConversationArchiveError.invalidSource(
                reason: "The portable format identifier or implementation is invalid."
            )
        }
        try validateDescriptor(manifest.conversation)
        guard manifest.conversation == document.conversation else {
            throw PortableConversationArchiveError.invalidSource(
                reason: "The manifest and document descriptors differ."
            )
        }
        guard manifest.document.path == "chat.json",
              isPortableSHA256(manifest.document.sha256),
              manifest.document.byteCount >= 0 else {
            throw PortableConversationArchiveError.invalidSource(
                reason: "The chat document declaration is invalid."
            )
        }
        guard manifest.media == manifest.media.sorted(by: { $0.path < $1.path }) else {
            throw PortableConversationArchiveError.invalidSource(
                reason: "Media declarations are not in canonical order."
            )
        }
        var declaredFiles: [String: PortableFileEntry] = [
            "chat.json": manifest.document
        ]
        for media in manifest.media {
            try validatePortableArchivePath(media.path)
            guard media.path.hasPrefix("Media/"),
                  media.byteCount >= 0,
                  isPortableSHA256(media.sha256),
                  declaredFiles[media.path] == nil else {
                throw PortableConversationArchiveError.invalidSource(
                    reason: "A media declaration is invalid or duplicated."
                )
            }
            declaredFiles[media.path] = PortableFileEntry(
                path: media.path,
                byteCount: media.byteCount,
                sha256: media.sha256
            )
        }
        guard Set(declaredFiles.keys) == Set(actualFiles.keys) else {
            throw PortableConversationArchiveError.invalidSource(
                reason: "Declared and physical files differ."
            )
        }
        for (path, declared) in declaredFiles {
            guard let actual = actualFiles[path],
                  actual.byteCount == declared.byteCount,
                  actual.sha256 == declared.sha256 else {
                throw PortableConversationArchiveError.integrityMismatch(path: path)
            }
        }
        guard manifest.messageCount == document.messages.count,
              document.messages == document.messages.sorted(by: portableMessagePrecedes) else {
            throw PortableConversationArchiveError.invalidSource(
                reason: "Message count or canonical order is invalid."
            )
        }
        let ids = document.messages.map(\.id)
        let idSet = Set(ids)
        guard idSet.count == ids.count,
              document.messages.allSatisfy({
                  $0.replyTo.map(idSet.contains) ?? true
              }) else {
            throw PortableConversationArchiveError.invalidSource(
                reason: "Message IDs or reply references are invalid."
            )
        }
        guard manifest.firstMessageAt == document.messages.first?.date,
              manifest.lastMessageAt == document.messages.last?.date else {
            throw PortableConversationArchiveError.invalidSource(
                reason: "Manifest message dates do not match chat.json."
            )
        }
        let declaredMediaPaths = Set(manifest.media.map(\.path))
        var referencedMediaPaths = Set<String>()
        if let photoPath = document.conversation.photoPath {
            referencedMediaPaths.insert(photoPath)
        }
        for contact in document.contacts {
            guard !contact.identity.addresses.isEmpty else {
                throw PortableConversationArchiveError.invalidSource(
                    reason: "A contact has no canonical identity."
                )
            }
            if let path = contact.photoPath { referencedMediaPaths.insert(path) }
        }
        for message in document.messages {
            try validatePortableMessage(message)
            if let path = message.mediaPath { referencedMediaPaths.insert(path) }
        }
        guard referencedMediaPaths == declaredMediaPaths else {
            throw PortableConversationArchiveError.invalidSource(
                reason: "Referenced and declared media differ."
            )
        }
        let expectedContentDigest = try portableContentDigest(
            schemaVersion: manifest.schemaVersion,
            conversation: manifest.conversation,
            document: manifest.document,
            media: manifest.media
        )
        guard manifest.contentDigest == expectedContentDigest else {
            throw PortableConversationArchiveError.integrityMismatch(
                path: "manifest.contentDigest"
            )
        }
    }

    func validateDescriptor(_ descriptor: PortableConversationDescriptor) throws {
        switch descriptor.chatType {
        case .group:
            guard let groupJID = descriptor.groupJID,
                  normalizedPortableJID(groupJID).hasSuffix("@g.us"),
                  groupJID == normalizedPortableJID(groupJID),
                  descriptor.contactJID == nil,
                  descriptor.contactIdentity == nil else {
                throw PortableConversationArchiveError.invalidSource(
                    reason: "The group descriptor is inconsistent."
                )
            }
        case .individual:
            guard descriptor.groupJID == nil,
                  descriptor.contactJID != nil
                    || descriptor.contactIdentity?.addresses.isEmpty == false else {
                throw PortableConversationArchiveError.invalidSource(
                    reason: "The individual descriptor has no counterpart identity."
                )
            }
        }
        if let photoPath = descriptor.photoPath {
            try validatePortableArchivePath(photoPath)
            guard photoPath.hasPrefix("Media/") else {
                throw PortableConversationArchiveError.unsafePath(photoPath)
            }
        }
    }

    func validatePortableMessage(_ message: PortableMessage) throws {
        switch message.author.role {
        case .sourceUser:
            guard message.author.identityHint == nil,
                  message.author.displayName == nil else {
                throw PortableConversationArchiveError.invalidSource(
                    reason: "A source-user author must not embed owner identity or name."
                )
            }
        case .participant:
            guard message.author.identityHint?.addresses.isEmpty == false else {
                throw PortableConversationArchiveError.invalidSource(
                    reason: "A participant author has no canonical identity."
                )
            }
        case .unresolved:
            guard message.author.identityHint == nil else {
                throw PortableConversationArchiveError.invalidSource(
                    reason: "An unresolved author contains an identity."
                )
            }
        }
        if let seconds = message.seconds, seconds < 0 {
            throw PortableConversationArchiveError.invalidSource(
                reason: "A message duration is negative."
            )
        }
        if let latitude = message.latitude,
           (!latitude.isFinite || !(-90...90).contains(latitude)) {
            throw PortableConversationArchiveError.invalidSource(
                reason: "A latitude is invalid."
            )
        }
        if let longitude = message.longitude,
           (!longitude.isFinite || !(-180...180).contains(longitude)) {
            throw PortableConversationArchiveError.invalidSource(
                reason: "A longitude is invalid."
            )
        }
        if let mediaPath = message.mediaPath {
            try validatePortableArchivePath(mediaPath)
            guard mediaPath.hasPrefix("Media/") else {
                throw PortableConversationArchiveError.unsafePath(mediaPath)
            }
        }
        for reaction in message.reactions ?? [] {
            switch reaction.author.role {
            case .sourceUser:
                guard reaction.author.identityHint == nil,
                      reaction.author.displayName == nil else {
                    throw PortableConversationArchiveError.invalidSource(
                        reason: "A source-user reaction embeds owner identity or name."
                    )
                }
            case .participant:
                guard reaction.author.identityHint?.addresses.isEmpty == false else {
                    throw PortableConversationArchiveError.invalidSource(
                        reason: "A participant reaction has no identity."
                    )
                }
            case .unresolved:
                guard reaction.author.identityHint == nil else {
                    throw PortableConversationArchiveError.invalidSource(
                        reason: "An unresolved reaction contains identity."
                    )
                }
            }
        }
    }

    func validatedDirectoryFiles(
        _ directory: URL
    ) throws -> [String: ValidatedDirectoryFile] {
        let values = try directory.resourceValues(
            forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        )
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw PortableConversationArchiveError.invalidDirectory(
                directory,
                reason: "The root is not a regular directory."
            )
        }
        let fileManager = FileManager.default
        let rootEntries = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey],
            options: []
        )
        let rootNames = Set(rootEntries.map(\.lastPathComponent))
        guard rootNames == Set(["manifest.json", "chat.json", "Media"]) else {
            throw PortableConversationArchiveError.invalidDirectory(
                directory,
                reason: "The root contains missing or extra entries."
            )
        }
        let mediaDirectory = directory.appendingPathComponent("Media", isDirectory: true)
        let mediaValues = try mediaDirectory.resourceValues(
            forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        )
        guard mediaValues.isDirectory == true, mediaValues.isSymbolicLink != true else {
            throw PortableConversationArchiveError.invalidDirectory(
                directory,
                reason: "Media is not a regular directory."
            )
        }
        let mediaURLs = try fileManager.contentsOfDirectory(
            at: mediaDirectory,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey],
            options: []
        )
        let fileURLs = [
            directory.appendingPathComponent("manifest.json"),
            directory.appendingPathComponent("chat.json")
        ] + mediaURLs
        guard fileURLs.count <= limits.maximumEntryCount else {
            throw PortableConversationArchiveError.limitExceeded(
                reason: "The directory contains too many files."
            )
        }
        var result: [String: ValidatedDirectoryFile] = [:]
        var foldedPaths = Set<String>()
        var total: Int64 = 0
        for url in fileURLs {
            let path = url.deletingLastPathComponent().standardizedFileURL.path
                == mediaDirectory.standardizedFileURL.path
                ? "Media/\(url.lastPathComponent)"
                : url.lastPathComponent
            try validatePortableArchivePath(path)
            guard foldedPaths.insert(path.lowercased()).inserted else {
                throw PortableConversationArchiveError.invalidDirectory(
                    directory,
                    reason: "The directory contains duplicate normalized paths."
                )
            }
            let values = try url.resourceValues(
                forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
            )
            guard values.isRegularFile == true, values.isSymbolicLink != true,
                  let fileSize = values.fileSize else {
                throw PortableConversationArchiveError.invalidDirectory(
                    directory,
                    reason: "A package entry is not a regular file."
                )
            }
            let byteCount = Int64(fileSize)
            let (newTotal, overflow) = total.addingReportingOverflow(byteCount)
            guard !overflow,
                  byteCount <= limits.maximumEntryByteCount,
                  newTotal <= limits.maximumUncompressedByteCount else {
                throw PortableConversationArchiveError.limitExceeded(
                    reason: "Directory contents exceed configured size limits."
                )
            }
            total = newTotal
            result[path] = ValidatedDirectoryFile(
                url: url,
                byteCount: byteCount,
                sha256: try portableSHA256File(url, cancellation: nil)
            )
        }
        return result
    }

    func readData(
        _ entry: ZIPFoundation.Entry,
        from archive: ZIPFoundation.Archive,
        maximumByteCount: Int64,
        cancellation: WABackupCancellationHandler?
    ) throws -> Data {
        var result = Data()
        _ = try archive.extract(entry) { chunk in
            try portableCheckCancellation(cancellation)
            guard Int64(result.count) + Int64(chunk.count) <= maximumByteCount else {
                throw PortableConversationArchiveError.limitExceeded(
                    reason: "A JSON entry exceeds the configured maximum."
                )
            }
            result.append(chunk)
        }
        return result
    }

    func hashEntry(
        _ entry: ZIPFoundation.Entry,
        from archive: ZIPFoundation.Archive,
        cancellation: WABackupCancellationHandler?
    ) throws -> (sha256: String, byteCount: Int64) {
#if canImport(CryptoKit)
        if #available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *) {
            return try cryptoHashEntry(
                entry,
                from: archive,
                cancellation: cancellation
            )
        }
#endif
        var hasher = ConversationSHA256()
        var byteCount: Int64 = 0
        _ = try archive.extract(entry) { chunk in
            try portableCheckCancellation(cancellation)
            let (newCount, overflow) = byteCount.addingReportingOverflow(Int64(chunk.count))
            guard !overflow, newCount <= limits.maximumEntryByteCount else {
                throw PortableConversationArchiveError.limitExceeded(
                    reason: "An extracted entry exceeds the configured maximum."
                )
            }
            byteCount = newCount
            hasher.update(data: chunk)
        }
        return (hasher.finalizeHex(), byteCount)
    }

#if canImport(CryptoKit)
    @available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
    func cryptoHashEntry(
        _ entry: ZIPFoundation.Entry,
        from archive: ZIPFoundation.Archive,
        cancellation: WABackupCancellationHandler?
    ) throws -> (sha256: String, byteCount: Int64) {
        var hasher = CryptoKit.SHA256()
        var byteCount: Int64 = 0
        _ = try archive.extract(entry) { chunk in
            try portableCheckCancellation(cancellation)
            let (newCount, overflow) = byteCount.addingReportingOverflow(Int64(chunk.count))
            guard !overflow, newCount <= limits.maximumEntryByteCount else {
                throw PortableConversationArchiveError.limitExceeded(
                    reason: "An extracted entry exceeds the configured maximum."
                )
            }
            byteCount = newCount
            hasher.update(data: chunk)
        }
        return (portableHex(hasher.finalize()), byteCount)
    }
#endif

    func extract(
        _ entry: ZIPFoundation.Entry,
        from archive: ZIPFoundation.Archive,
        to outputURL: URL,
        cancellation: WABackupCancellationHandler?
    ) throws {
        guard FileManager.default.createFile(atPath: outputURL.path, contents: nil) else {
            throw PortableConversationArchiveError.fileOperation(
                outputURL,
                underlying: CocoaError(.fileWriteUnknown)
            )
        }
        let handle = try FileHandle(forWritingTo: outputURL)
        defer { handle.closeFile() }
        var count: Int64 = 0
        _ = try archive.extract(entry) { chunk in
            try portableCheckCancellation(cancellation)
            let (newCount, overflow) = count.addingReportingOverflow(Int64(chunk.count))
            guard !overflow, newCount <= limits.maximumEntryByteCount else {
                throw PortableConversationArchiveError.limitExceeded(
                    reason: "An extracted entry exceeds the configured maximum."
                )
            }
            count = newCount
            handle.write(chunk)
        }
        let expectedCount = try checkedInt64(entry.uncompressedSize)
        guard count == expectedCount else {
            throw PortableConversationArchiveError.integrityMismatch(path: entry.path)
        }
    }

    func addFile(
        _ fileURL: URL,
        path: String,
        to archive: ZIPFoundation.Archive,
        cancellation: WABackupCancellationHandler?
    ) throws {
        let values = try fileURL.resourceValues(
            forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        )
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              let fileSize = values.fileSize else {
            throw PortableConversationArchiveError.fileOperation(
                fileURL,
                underlying: CocoaError(.fileReadUnknown)
            )
        }
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { handle.closeFile() }
        try archive.addEntry(
            with: path,
            type: .file,
            uncompressedSize: Int64(fileSize),
            modificationDate: Date(timeIntervalSince1970: 0),
            permissions: 0o644,
            compressionMethod: .deflate
        ) { position, size in
            try portableCheckCancellation(cancellation)
            handle.seek(toFileOffset: UInt64(position))
            return handle.readData(ofLength: size)
        }
    }

    func installArchive(
        _ temporaryURL: URL,
        at destinationURL: URL,
        overwriteExisting: Bool
    ) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: destinationURL.path) else {
            try fileManager.moveItem(at: temporaryURL, to: destinationURL)
            return
        }
        guard overwriteExisting else {
            throw PortableConversationArchiveError.archiveAlreadyExists(destinationURL)
        }
        let backupURL = destinationURL.deletingLastPathComponent().appendingPathComponent(
            ".replacing-\(UUID().uuidString).fmcchat"
        )
        try fileManager.moveItem(at: destinationURL, to: backupURL)
        do {
            try fileManager.moveItem(at: temporaryURL, to: destinationURL)
            try fileManager.removeItem(at: backupURL)
        } catch {
            if fileManager.fileExists(atPath: destinationURL.path) {
                try? fileManager.removeItem(at: destinationURL)
            }
            try? fileManager.moveItem(at: backupURL, to: destinationURL)
            throw error
        }
    }

    func prepareEmptyDestination(_ destination: URL) throws -> Bool {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: destination.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue,
                  (try fileManager.contentsOfDirectory(atPath: destination.path)).isEmpty,
                  try destination.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink
                    != true else {
                throw PortableConversationArchiveError.destinationNotEmpty(destination)
            }
            return false
        }
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: false)
        return true
    }

    func validateLimits() throws {
        guard limits.maximumArchiveByteCount > 0,
              limits.maximumUncompressedByteCount > 0,
              limits.maximumEntryByteCount > 0,
              limits.maximumJSONByteCount > 0,
              limits.maximumEntryCount >= 2,
              limits.maximumCompressionRatio >= 1,
              limits.maximumPathUTF8ByteCount >= 32 else {
            throw PortableConversationArchiveError.limitExceeded(
                reason: "The configured limits are invalid."
            )
        }
    }

    func checkedInt64(_ value: UInt64) throws -> Int64 {
        guard value <= UInt64(Int64.max) else {
            throw PortableConversationArchiveError.limitExceeded(
                reason: "An entry size cannot be represented safely."
            )
        }
        return Int64(value)
    }

    func portableContentDigest(
        schemaVersion: Int,
        conversation: PortableConversationDescriptor,
        document: PortableFileEntry,
        media: [PortableMediaEntry]
    ) throws -> String {
        let payload = PortableContentDigestPayload(
            schemaVersion: schemaVersion,
            conversation: conversation,
            document: document,
            media: media.sorted { $0.path < $1.path }
        )
        return portableSHA256(try portableCanonicalJSONEncoder().encode(payload))
    }
}

private extension PortableConversationDirectory {
    func messageAuthor(from author: PortableMessageAuthor) -> MessageAuthor? {
        switch author.role {
        case .sourceUser:
            return MessageAuthor(
                kind: .me,
                displayName: author.displayName,
                phone: nil,
                jid: nil,
                source: .owner
            )
        case .participant:
            return participantMessageAuthor(author)
        case .unresolved:
            return nil
        }
    }

    func reactionAuthor(from author: PortableMessageAuthor) -> MessageAuthor {
        messageAuthor(from: author) ?? MessageAuthor(
            kind: .participant,
            displayName: author.displayName,
            phone: nil,
            jid: nil,
            source: .messageJid
        )
    }

    func participantMessageAuthor(_ author: PortableMessageAuthor) -> MessageAuthor? {
        guard let identity = author.identityHint else { return nil }
        let phone = identity.comparisonKeys
            .filter { $0.hasPrefix("phone:") }
            .sorted()
            .first
            .map { String($0.dropFirst("phone:".count)) }
        let jid = identity.addresses.first(where: {
            $0.kind == .phoneJID || $0.kind == .lidJID
        })?.value ?? phone.map { "\($0)@s.whatsapp.net" }
        return MessageAuthor(
            kind: .participant,
            displayName: author.displayName,
            phone: phone,
            jid: jid,
            source: .messageJid
        )
    }

    func portableContactJID(_ descriptor: PortableConversationDescriptor) throws -> String {
        if descriptor.chatType == .group, let groupJID = descriptor.groupJID {
            return groupJID
        }
        if let contactJID = descriptor.contactJID {
            return contactJID
        }
        if let address = descriptor.contactIdentity?.addresses.first {
            switch address.kind {
            case .phone:
                return "\(address.value)@s.whatsapp.net"
            case .phoneJID, .lidJID:
                return address.value
            }
        }
        throw PortableConversationArchiveError.invalidDirectory(
            directoryURL,
            reason: "The conversation has no usable contact JID."
        )
    }
}

private extension ConversationSource {
    init(
        portableID: ConversationSourceID,
        document: ExportedChatDocument,
        mediaDirectoryURL: URL,
        conversationIdentityHint: CanonicalParticipantIdentity?,
        perspectiveHint: ConversationPerspectiveHint?,
        stableMessageIDs: [Int: ArchiveMessageID]
    ) throws {
        guard !portableID.rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ConversationCompositionError.invalidSource(
                sourceID: portableID,
                reason: "The source identifier is empty."
            )
        }
        self.id = portableID
        self.kind = .portableDocument
        self.conversationIdentityHint = conversationIdentityHint
        self.perspectiveHint = perspectiveHint
        self.sourceDate = document.exportedAt
        self.document = document
        self.mediaDirectoryURL = mediaDirectoryURL.standardizedFileURL
        self.stableMessageIDs = stableMessageIDs
    }
}

private func portableDescriptor(
    from source: ConversationSource,
    mediaPathByFilename: [String: String]
) throws -> PortableConversationDescriptor {
    let chat = source.document.chat
    switch chat.chatType {
    case .group:
        let groupJID = normalizedPortableJID(chat.contactJid)
        guard groupJID.hasSuffix("@g.us") else {
            throw PortableConversationArchiveError.invalidSource(
                reason: "The group JID is invalid."
            )
        }
        return PortableConversationDescriptor(
            chatType: .group,
            groupJID: groupJID,
            displayName: chat.name,
            isArchived: chat.isArchived,
            exportedAt: source.document.exportedAt,
            photoPath: chat.photoFilename.flatMap { mediaPathByFilename[$0] }
        )
    case .individual:
        var addresses = portableParticipantAddresses(chat.contactJid)
        if let hint = source.conversationIdentityHint {
            addresses.append(contentsOf: hint.addresses)
        }
        let identity = CanonicalParticipantIdentity(addresses: addresses)
        guard !identity.addresses.isEmpty else {
            throw PortableConversationArchiveError.invalidSource(
                reason: "The individual counterpart has no canonical identity."
            )
        }
        return PortableConversationDescriptor(
            chatType: .individual,
            contactJID: normalizedPortableJID(chat.contactJid),
            contactIdentity: identity,
            displayName: chat.name,
            isArchived: chat.isArchived,
            exportedAt: source.document.exportedAt,
            photoPath: chat.photoFilename.flatMap { mediaPathByFilename[$0] }
        )
    }
}

private func portableAuthor(
    isFromMe: Bool,
    author: MessageAuthor?,
    individualFallback: CanonicalParticipantIdentity?
) -> PortableMessageAuthor {
    if isFromMe {
        return PortableMessageAuthor(role: .sourceUser)
    }
    let addresses = author.map {
        [$0.phone, $0.jid].compactMap { $0 }.flatMap(portableParticipantAddresses)
    } ?? []
    let identity = CanonicalParticipantIdentity(addresses: addresses)
    let resolvedIdentity = identity.addresses.isEmpty ? individualFallback : identity
    if let resolvedIdentity, !resolvedIdentity.addresses.isEmpty {
        return PortableMessageAuthor(
            role: .participant,
            identityHint: resolvedIdentity,
            displayName: author?.displayName
        )
    }
    return PortableMessageAuthor(role: .unresolved, displayName: author?.displayName)
}

private func portableParticipantAddresses(_ value: String) -> [ParticipantAddress] {
    let normalized = normalizedPortableJID(value)
    if normalized.hasSuffix("@s.whatsapp.net") {
        return [ParticipantAddress(kind: .phoneJID, value: normalized)]
    }
    if normalized.hasSuffix("@lid") {
        return [ParticipantAddress(kind: .lidJID, value: normalized)]
    }
    let digits = value.filter(\.isNumber)
    if !digits.isEmpty, value.allSatisfy({ $0.isNumber || $0 == "+" }) {
        return [ParticipantAddress(kind: .phone, value: digits)]
    }
    return []
}

private func normalizedPortableJID(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
        .precomposedStringWithCanonicalMapping
        .lowercased()
}

private func portableMediaFilename(digest: String, originalFilename: String) -> String {
    let candidate = "\(digest)-\(originalFilename.precomposedStringWithCanonicalMapping)"
    if candidate.utf8.count <= 240 {
        return candidate
    }
    let extensionPart = URL(fileURLWithPath: originalFilename).pathExtension
    return extensionPart.isEmpty ? digest : "\(digest).\(extensionPart)"
}

private func isSafePortableMediaFilename(_ filename: String) -> Bool {
    !filename.isEmpty
        && filename == filename.precomposedStringWithCanonicalMapping
        && filename == URL(fileURLWithPath: filename).lastPathComponent
        && filename != "."
        && filename != ".."
        && !filename.hasPrefix(".")
        && !filename.contains("/")
        && !filename.contains("\\")
        && !filename.contains("\0")
        && !filename.contains(":")
        && filename.unicodeScalars.allSatisfy {
            !CharacterSet.controlCharacters.contains($0)
        }
}

private func portableMessagePrecedes(_ lhs: PortableMessage, _ rhs: PortableMessage) -> Bool {
    if lhs.date != rhs.date { return lhs.date < rhs.date }
    return lhs.id.rawValue.uuidString < rhs.id.rawValue.uuidString
}

private func portableStableMessageSeed(
    _ message: MessageInfo,
    occurrence: Int
) throws -> String {
    struct Seed: Encodable {
        let occurrence: Int
        let date: Date
        let isFromMe: Bool
        let messageType: String
        let text: String?
        let caption: String?
        let mediaFilename: String?
        let seconds: Int?
        let latitude: Double?
        let longitude: Double?
    }
    return portableSHA256(
        try portableCanonicalJSONEncoder().encode(
            Seed(
                occurrence: occurrence,
                date: message.date,
                isFromMe: message.isFromMe,
                messageType: message.messageType,
                text: message.message,
                caption: message.caption,
                mediaFilename: message.mediaFilename,
                seconds: message.seconds,
                latitude: message.latitude,
                longitude: message.longitude
            )
        )
    )
}

private func portableDeterministicUUID(seed: String) -> UUID {
    var bytes: [UInt8] = stride(from: 0, to: 32, by: 2).compactMap { offset in
        let start = seed.index(seed.startIndex, offsetBy: offset)
        let end = seed.index(start, offsetBy: 2)
        return UInt8(seed[start..<end], radix: 16)
    }
    while bytes.count < 16 { bytes.append(0) }
    bytes[6] = (bytes[6] & 0x0F) | 0x50
    bytes[8] = (bytes[8] & 0x3F) | 0x80
    return UUID(uuid: (
        bytes[0], bytes[1], bytes[2], bytes[3],
        bytes[4], bytes[5], bytes[6], bytes[7],
        bytes[8], bytes[9], bytes[10], bytes[11],
        bytes[12], bytes[13], bytes[14], bytes[15]
    ))
}

private func portableJSONEncoder() -> JSONEncoder {
    let encoder = portableCanonicalJSONEncoder()
    if #available(macOS 10.15, *) {
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    } else {
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }
    return encoder
}

private func portableCanonicalJSONEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    if #available(macOS 10.15, *) {
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    } else {
        encoder.outputFormatting = [.sortedKeys]
    }
    encoder.dateEncodingStrategy = .custom { date, dateEncoder in
        var container = dateEncoder.singleValueContainer()
        try container.encode(portableDateFormatter().string(from: date))
    }
    return encoder
}

private func portableJSONDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { dateDecoder in
        let container = try dateDecoder.singleValueContainer()
        let value = try container.decode(String.self)
        guard let date = portableDateFormatter().date(from: value) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected UTC RFC 3339 with milliseconds."
            )
        }
        return date
    }
    return decoder
}

private func portableDateFormatter() -> ISO8601DateFormatter {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [
        .withInternetDateTime,
        .withFractionalSeconds,
        .withDashSeparatorInDate,
        .withColonSeparatorInTime
    ]
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    return formatter
}

private func portableSHA256(_ data: Data) -> String {
#if canImport(CryptoKit)
    if #available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *) {
        return portableHex(CryptoKit.SHA256.hash(data: data))
    }
#endif
    return ConversationSHA256.hashHex(data)
}

private func portableSHA256File(
    _ url: URL,
    cancellation: WABackupCancellationHandler?
) throws -> String {
#if canImport(CryptoKit)
    if #available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *) {
        return try portableCryptoSHA256File(url, cancellation: cancellation)
    }
#endif
    let handle = try FileHandle(forReadingFrom: url)
    defer { handle.closeFile() }
    var hasher = ConversationSHA256()
    while true {
        try portableCheckCancellation(cancellation)
        let chunk = handle.readData(ofLength: 1_048_576)
        if chunk.isEmpty { break }
        hasher.update(data: chunk)
    }
    return hasher.finalizeHex()
}

#if canImport(CryptoKit)
@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
private func portableCryptoSHA256File(
    _ url: URL,
    cancellation: WABackupCancellationHandler?
) throws -> String {
    let handle = try FileHandle(forReadingFrom: url)
    defer { handle.closeFile() }
    var hasher = CryptoKit.SHA256()
    while true {
        try portableCheckCancellation(cancellation)
        let chunk = handle.readData(ofLength: 1_048_576)
        if chunk.isEmpty { break }
        hasher.update(data: chunk)
    }
    return portableHex(hasher.finalize())
}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
private func portableHex<D: Sequence>(_ digest: D) -> String
where D.Element == UInt8 {
    let table = Array("0123456789abcdef".utf8)
    var result = [UInt8]()
    result.reserveCapacity(64)
    for byte in digest {
        result.append(table[Int(byte >> 4)])
        result.append(table[Int(byte & 0x0f)])
    }
    return String(decoding: result, as: UTF8.self)
}
#endif

private func isPortableSHA256(_ value: String) -> Bool {
    let allowed = CharacterSet(charactersIn: "0123456789abcdef")
    return value.utf8.count == 64
        && value.unicodeScalars.allSatisfy(allowed.contains)
}

private func portableCheckCancellation(
    _ cancellation: WABackupCancellationHandler?
) throws {
    if cancellation?() == true {
        throw PortableConversationArchiveError.cancelled
    }
}

private func portableMappedError(_ error: Error, url: URL) -> Error {
    if error is PortableConversationArchiveError { return error }
    if let composition = error as? ConversationCompositionError {
        if case .cancelled = composition {
            return PortableConversationArchiveError.cancelled
        }
    }
    return PortableConversationArchiveError.invalidArchive(
        url,
        reason: error.localizedDescription
    )
}

private func portableMappedDirectoryError(_ error: Error, url: URL) -> Error {
    if let portable = error as? PortableConversationArchiveError {
        if case .invalidSource(let reason) = portable {
            return PortableConversationArchiveError.invalidDirectory(url, reason: reason)
        }
        return portable
    }
    return PortableConversationArchiveError.invalidDirectory(
        url,
        reason: error.localizedDescription
    )
}

private func portableMappedArchiveInspectionError(
    _ error: Error,
    url: URL
) -> Error {
    if let portable = error as? PortableConversationArchiveError {
        switch portable {
        case .invalidSource(let reason), .invalidDirectory(_, let reason):
            return PortableConversationArchiveError.invalidArchive(url, reason: reason)
        default:
            return portable
        }
    }
    return portableMappedError(error, url: url)
}

//
//  ExtractedWhatsAppBackup.swift
//  SwiftWABackupAPI
//

import Foundation
import GRDB

let whatsAppBackupDomain = "AppDomainGroup-group.net.whatsapp.WhatsApp.shared"

struct WhatsAppFileDetails {
    let filename: String
    let sourceURL: URL
}

private struct WhatsAppBackupEntry {
    enum EntryType {
        case file
        case directory
        case other

        var indexValue: String {
            switch self {
            case .file:
                return "file"
            case .directory:
                return "directory"
            case .other:
                return "other"
            }
        }
    }

    let filename: String
    let fileHash: String
    let type: EntryType
}

/// Represents a WhatsApp app-group backup previously extracted from an iPhone backup.
public struct ExtractedWhatsAppBackup {
    /// Root directory that contains the extracted WhatsApp files.
    public let url: URL

    /// Absolute path of the extracted WhatsApp directory.
    public var path: String {
        url.path
    }

    /// Creates an extracted WhatsApp backup rooted at the provided directory.
    public init(url: URL) {
        self.url = url
    }

    /// Creates an extracted WhatsApp backup rooted at the provided path.
    public init(path: String) {
        self.init(url: URL(fileURLWithPath: path, isDirectory: true))
    }
}

extension ExtractedWhatsAppBackup {
    func fileURL(endingWith relativePath: String) throws -> URL {
        try validateRelativePath(relativePath)
        let normalizedPath = normalizedWhatsAppRelativePath(relativePath)

        for candidate in directFileURLCandidates(for: normalizedPath) {
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }

        throw DomainError.mediaNotFound(path: relativePath)
    }

    func mediaReference(sourceURL: URL) throws -> MediaReference {
        let resolvedRelativePath = try relativePathWithinBackup(for: sourceURL)
        let values = try? sourceURL.resourceValues(forKeys: [.fileSizeKey])
        let byteCount = values?.fileSize.map(Int64.init)

        return MediaReference(
            relativePath: resolvedRelativePath,
            filename: sourceURL.lastPathComponent,
            byteCount: byteCount,
            mimeType: MediaReference.inferredMIMEType(for: sourceURL.lastPathComponent)
        )
    }

    private func validateRelativePath(_ relativePath: String) throws {
        let normalizedPath = normalizedWhatsAppRelativePath(relativePath)
        let components = normalizedPath.split(separator: "/").map(String.init)

        guard !normalizedPath.isEmpty,
              !components.contains("..") else {
            throw BackupError.invalidBackup(
                url: url,
                reason: "Unsafe WhatsApp relative path: \(relativePath)"
            )
        }
    }

    private func relativePathWithinBackup(for fileURL: URL) throws -> String {
        let rootPath = url.standardizedFileURL.path
        let filePath = fileURL.standardizedFileURL.path

        guard filePath.hasPrefix(rootPath + "/") else {
            throw BackupError.invalidBackup(
                url: url,
                reason: "Resolved file is outside the extracted WhatsApp backup: \(filePath)"
            )
        }

        return String(filePath.dropFirst(rootPath.count + 1))
    }

    private func directFileURLCandidates(for normalizedPath: String) -> [URL] {
        var candidates = [url.appendingPathComponent(normalizedPath)]

        if normalizedPath.hasPrefix("Media/"),
           !normalizedPath.hasPrefix("Media/Profile/") {
            candidates.append(url.appendingPathComponent("Message").appendingPathComponent(normalizedPath))
        }

        return candidates
    }

    func fileDetails(containing relativePath: String) throws -> [WhatsAppFileDetails] {
        let normalizedPath = normalizedWhatsAppRelativePath(relativePath)

        guard !normalizedPath.isEmpty else {
            return []
        }

        if normalizedPath.hasPrefix("Media/Profile/") {
            return try profileFileDetails(containing: normalizedPath)
        }

        return try fileDetailsInDirectDirectory(containing: normalizedPath)
    }

    func allProfileFileDetails() throws -> [WhatsAppFileDetails] {
        try fileDetails(
            inDirectoryAtRelativePath: "Media/Profile",
            matching: { _ in true }
        )
    }

    private func profileFileDetails(containing normalizedPath: String) throws -> [WhatsAppFileDetails] {
        try fileDetails(
            inDirectoryAtRelativePath: "Media/Profile",
            matching: { $0.contains(normalizedPath) }
        )
    }

    private func fileDetailsInDirectDirectory(containing normalizedPath: String) throws -> [WhatsAppFileDetails] {
        let pathComponents = normalizedPath.split(separator: "/").map(String.init)
        guard pathComponents.count > 1 else {
            return []
        }

        let directoryRelativePath = pathComponents.dropLast().joined(separator: "/")
        return try fileDetails(
            inDirectoryAtRelativePath: directoryRelativePath,
            matching: { $0.contains(normalizedPath) }
        )
    }

    private func fileDetails(
        inDirectoryAtRelativePath directoryRelativePath: String,
        matching predicate: (String) -> Bool
    ) throws -> [WhatsAppFileDetails] {
        let fileManager = FileManager.default
        let directoryURL = url.appendingPathComponent(directoryRelativePath, isDirectory: true)

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return []
        }

        let contents = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: []
        )
        var files: [WhatsAppFileDetails] = []

        for fileURL in contents {
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else {
                continue
            }

            let relativePath = directoryRelativePath + "/" + fileURL.lastPathComponent
            guard predicate(relativePath) else {
                continue
            }

            files.append(WhatsAppFileDetails(filename: relativePath, sourceURL: fileURL))
        }

        return files
    }
}

public extension ExtractedWhatsAppBackup {
    /// Resolves a portable relative path to an existing file inside this extracted backup.
    ///
    /// WhatsApp media aliases such as `Media/...` are resolved to their extracted
    /// `Message/Media/...` location when necessary. Leading separators are normalized,
    /// while parent-directory traversal is rejected.
    func resolveFileURL(relativePath: String) throws -> URL {
        try fileURL(endingWith: relativePath)
    }
}

public extension IPhoneBackup {
    /// Copies available files from WhatsApp's iOS app-group domain into a regular directory tree.
    ///
    /// The extracted directory can be used later with `ExtractedWhatsAppBackup`
    /// without reading the original iPhone backup or its `Manifest.db` again.
    @discardableResult
    func extractWhatsAppBackup(
        to destinationDirectory: URL,
        overwriteExisting: Bool = false,
        progress: WABackupProgressHandler? = nil
    ) throws -> ExtractedWhatsAppBackup {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        reportProgress(
            progress,
            phase: .loadingManifest,
            completedUnitCount: 0,
            unit: .manifestEntries,
            currentItem: "Manifest.db"
        )
        let entries = try fetchAllWhatsAppBackupEntries()
        reportProgress(
            progress,
            phase: .loadingManifest,
            completedUnitCount: entries.count,
            totalUnitCount: entries.count,
            unit: .manifestEntries,
            currentItem: "Manifest.db"
        )

        reportProgress(
            progress,
            phase: .copyingBackupFiles,
            completedUnitCount: 0,
            totalUnitCount: entries.count,
            unit: .manifestEntries
        )

        for (index, entry) in entries.enumerated() {
            let targetURL = try extractedTargetURL(
                forWhatsAppRelativePath: entry.filename,
                under: destinationDirectory
            )
            let completed = index + 1

            switch entry.type {
            case .directory:
                try fileManager.createDirectory(at: targetURL, withIntermediateDirectories: true)
                reportProgress(
                    progress,
                    phase: .copyingBackupFiles,
                    completedUnitCount: completed,
                    totalUnitCount: entries.count,
                    unit: .manifestEntries,
                    currentItem: entry.filename
                )
                continue

            case .other:
                reportProgress(
                    progress,
                    phase: .copyingBackupFiles,
                    completedUnitCount: completed,
                    totalUnitCount: entries.count,
                    unit: .manifestEntries,
                    currentItem: entry.filename
                )
                continue

            case .file:
                break
            }

            let sourceURL = getUrl(fileHash: entry.fileHash)
            try fileManager.createDirectory(
                at: targetURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            if fileManager.fileExists(atPath: targetURL.path) {
                guard overwriteExisting else {
                    reportProgress(
                        progress,
                        phase: .copyingBackupFiles,
                        completedUnitCount: completed,
                        totalUnitCount: entries.count,
                        unit: .manifestEntries,
                        currentItem: entry.filename
                    )
                    continue
                }

                try fileManager.removeItem(at: targetURL)
            }

            do {
                try fileManager.copyItem(at: sourceURL, to: targetURL)
            } catch {
                throw BackupError.fileCopy(
                    source: sourceURL,
                    destination: targetURL,
                    underlying: error
                )
            }

            reportProgress(
                progress,
                phase: .copyingBackupFiles,
                completedUnitCount: completed,
                totalUnitCount: entries.count,
                unit: .manifestEntries,
                currentItem: entry.filename
            )
        }

        try writePortableMetadata(for: entries, under: destinationDirectory, progress: progress)
        let extractedBackup = ExtractedWhatsAppBackup(url: destinationDirectory)
        reportProgress(
            progress,
            phase: .completed,
            completedUnitCount: 1,
            totalUnitCount: 1,
            unit: .phases,
            currentItem: "extractWhatsAppBackup"
        )
        return extractedBackup
    }
}

public extension ExtractedWhatsAppBackup {
    /// Opens this extracted WhatsApp backup for chat listing and export.
    ///
    /// When `exportRootDirectory` is provided, profile photos are exported to
    /// `ChatProfilePhotos` and chat media to `Chats/<chatId>/Media` below it.
    /// Per-call output directories still take precedence.
    func openReader(exportRootDirectory: URL? = nil) throws -> WhatsAppBackupReader {
        try WhatsAppBackupReader(backup: self, exportRootDirectory: exportRootDirectory)
    }

    /// Reads the portable summary generated at `.wa-backup/backup-info.json`.
    func getBackupInfo() throws -> ExtractedWhatsAppBackupInfo {
        let infoURL = url
            .appendingPathComponent(".wa-backup", isDirectory: true)
            .appendingPathComponent("backup-info.json")

        do {
            let data = try Data(contentsOf: infoURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(ExtractedWhatsAppBackupInfo.self, from: data)
        } catch {
            throw BackupError.invalidBackup(
                url: url,
                reason: "Could not read .wa-backup/backup-info.json: \(error.localizedDescription)"
            )
        }
    }
}

private extension IPhoneBackup {
    func fetchAllWhatsAppBackupEntries() throws -> [WhatsAppBackupEntry] {
        let manifestDBPath = url.appendingPathComponent("Manifest.db").path
        let manifestDb: DatabaseQueue

        do {
            manifestDb = try DatabaseQueue(path: manifestDBPath)
        } catch {
            throw DatabaseErrorWA.connection(error)
        }

        do {
            return try manifestDb.read { db in
                let rows = try Row.fetchAll(
                    db,
                    sql: """
                    SELECT fileID, relativePath, flags FROM Files
                    WHERE domain = ?
                      AND relativePath IS NOT NULL
                      AND relativePath <> ''
                    ORDER BY relativePath ASC
                    """,
                    arguments: [whatsAppBackupDomain]
                )

                return rows.compactMap { row in
                    guard let fileHash = row["fileID"] as? String,
                          let filename = row["relativePath"] as? String else {
                        return nil
                    }

                    let flags = row.value(for: "flags", default: Int64(1))
                    return WhatsAppBackupEntry(
                        filename: filename,
                        fileHash: fileHash,
                        type: entryType(for: flags)
                    )
                }
            }
        } catch {
            throw DatabaseErrorWA.connection(error)
        }
    }

    func extractedTargetURL(forWhatsAppRelativePath relativePath: String, under rootURL: URL) throws -> URL {
        let normalizedPath = normalizedWhatsAppRelativePath(relativePath)
        let components = normalizedPath.split(separator: "/").map(String.init)

        guard !normalizedPath.isEmpty,
              !normalizedPath.hasPrefix("/"),
              !components.contains("..") else {
            throw BackupError.invalidBackup(url: url, reason: "Unsafe WhatsApp relative path: \(relativePath)")
        }

        var targetURL = rootURL
        for component in components {
            targetURL.appendPathComponent(component)
        }

        let rootPath = rootURL.standardizedFileURL.path
        let targetPath = targetURL.standardizedFileURL.path
        guard targetPath == rootPath || targetPath.hasPrefix(rootPath + "/") else {
            throw BackupError.invalidBackup(url: url, reason: "Unsafe WhatsApp relative path: \(relativePath)")
        }

        return targetURL
    }

    func entryType(for flags: Int64) -> WhatsAppBackupEntry.EntryType {
        switch flags {
        case 1:
            return .file
        case 2:
            return .directory
        default:
            return .other
        }
    }

    func writePortableMetadata(
        for entries: [WhatsAppBackupEntry],
        under rootURL: URL,
        progress: WABackupProgressHandler? = nil
    ) throws {
        let sidecarURL = rootURL.appendingPathComponent(".wa-backup", isDirectory: true)
        reportProgress(
            progress,
            phase: .writingMetadata,
            completedUnitCount: 0,
            totalUnitCount: 3,
            unit: .phases,
            currentItem: ".wa-backup"
        )
        try FileManager.default.createDirectory(at: sidecarURL, withIntermediateDirectories: true)
        let indexURL = try writePortableIndex(
            for: entries,
            rootURL: rootURL,
            sidecarURL: sidecarURL,
            progress: progress
        )
        reportProgress(
            progress,
            phase: .writingMetadata,
            completedUnitCount: 1,
            totalUnitCount: 3,
            unit: .phases,
            currentItem: "index.sqlite"
        )
        try writeBackupInfo(
            for: entries,
            rootURL: rootURL,
            sidecarURL: sidecarURL,
            indexURL: indexURL,
            progress: progress
        )
        reportProgress(
            progress,
            phase: .writingMetadata,
            completedUnitCount: 2,
            totalUnitCount: 3,
            unit: .phases,
            currentItem: "backup-info.json"
        )
        try writePortableReadme(to: sidecarURL)
        reportProgress(
            progress,
            phase: .writingMetadata,
            completedUnitCount: 3,
            totalUnitCount: 3,
            unit: .phases,
            currentItem: "README.md"
        )
    }

    func writePortableIndex(
        for entries: [WhatsAppBackupEntry],
        rootURL: URL,
        sidecarURL: URL,
        progress: WABackupProgressHandler? = nil
    ) throws -> URL {
        let fileManager = FileManager.default
        let indexURL = sidecarURL.appendingPathComponent("index.sqlite")

        if fileManager.fileExists(atPath: indexURL.path) {
            try fileManager.removeItem(at: indexURL)
        }

        let indexQueue = try DatabaseQueue(path: indexURL.path)
        let generatedAt = ISO8601DateFormatter().string(from: Date())
        let creationDateString = ISO8601DateFormatter().string(from: creationDate)

        try indexQueue.write { db in
            try createPortableIndexSchema(in: db)
            try insertPortableIndexMetadata(
                in: db,
                generatedAt: generatedAt,
                creationDateString: creationDateString
            )

            let fileEntriesByPath = try insertPortableIndexFiles(
                entries,
                rootURL: rootURL,
                in: db,
                progress: progress
            )

            try insertPortableIndexPathAliases(entries, in: db, progress: progress)
            try insertPortableIndexMediaItems(
                fileEntriesByPath: fileEntriesByPath,
                rootURL: rootURL,
                in: db,
                progress: progress
            )
        }

        return indexURL
    }

    func createPortableIndexSchema(in db: Database) throws {
        try db.execute(sql: """
            CREATE TABLE metadata (
                key TEXT PRIMARY KEY NOT NULL,
                value TEXT NOT NULL
            )
            """)

        try db.execute(sql: """
            CREATE TABLE files (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                file_id TEXT NOT NULL,
                domain TEXT NOT NULL,
                manifest_relative_path TEXT NOT NULL,
                normalized_relative_path TEXT NOT NULL,
                extracted_relative_path TEXT NOT NULL,
                entry_type TEXT NOT NULL,
                exists_on_disk INTEGER NOT NULL,
                byte_count INTEGER
            )
            """)

        try db.execute(sql: """
            CREATE INDEX files_normalized_relative_path_idx
            ON files(normalized_relative_path)
            """)

        try db.execute(sql: """
            CREATE INDEX files_extracted_relative_path_idx
            ON files(extracted_relative_path)
            """)

        try db.execute(sql: """
            CREATE TABLE path_aliases (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                alias_path TEXT NOT NULL,
                normalized_alias_path TEXT NOT NULL,
                extracted_relative_path TEXT NOT NULL,
                reason TEXT NOT NULL,
                file_id TEXT,
                UNIQUE(alias_path, extracted_relative_path, reason)
            )
            """)

        try db.execute(sql: """
            CREATE INDEX path_aliases_normalized_alias_path_idx
            ON path_aliases(normalized_alias_path)
            """)

        try db.execute(sql: """
            CREATE TABLE media_items (
                media_item_id INTEGER PRIMARY KEY,
                local_path TEXT NOT NULL,
                normalized_local_path TEXT NOT NULL,
                resolved_relative_path TEXT,
                resolution_status TEXT NOT NULL,
                file_id TEXT,
                manifest_relative_path TEXT
            )
            """)
    }

    func insertPortableIndexMetadata(
        in db: Database,
        generatedAt: String,
        creationDateString: String
    ) throws {
        let values = [
            ("schema_version", "1"),
            ("generator", "SwiftWABackupAPI"),
            ("generated_at", generatedAt),
            ("source_iphone_backup_id", identifier),
            ("source_iphone_backup_creation_date", creationDateString),
            ("source_domain", whatsAppBackupDomain),
            ("path_semantics", "All stored paths are relative to the extracted WhatsApp backup root.")
        ]

        for (key, value) in values {
            try db.execute(
                sql: "INSERT INTO metadata (key, value) VALUES (?, ?)",
                arguments: [key, value]
            )
        }
    }

    func insertPortableIndexFiles(
        _ entries: [WhatsAppBackupEntry],
        rootURL: URL,
        in db: Database,
        progress: WABackupProgressHandler? = nil
    ) throws -> [String: WhatsAppBackupEntry] {
        var fileEntriesByPath: [String: WhatsAppBackupEntry] = [:]
        reportProgress(
            progress,
            phase: .indexingFiles,
            completedUnitCount: 0,
            totalUnitCount: entries.count,
            unit: .manifestEntries
        )

        for (index, entry) in entries.enumerated() {
            let normalizedPath = normalizedWhatsAppRelativePath(entry.filename)
            let targetURL = rootURL.appendingPathComponent(normalizedPath)
            let existsOnDisk = FileManager.default.fileExists(atPath: targetURL.path) ? 1 : 0
            let byteCount = entry.type == .file ? fileByteCount(at: targetURL) : nil

            try db.execute(
                sql: """
                    INSERT INTO files (
                        file_id,
                        domain,
                        manifest_relative_path,
                        normalized_relative_path,
                        extracted_relative_path,
                        entry_type,
                        exists_on_disk,
                        byte_count
                    )
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    entry.fileHash,
                    whatsAppBackupDomain,
                    entry.filename,
                    normalizedPath,
                    normalizedPath,
                    entry.type.indexValue,
                    existsOnDisk,
                    byteCount
                ]
            )

            if entry.type == .file {
                fileEntriesByPath[normalizedPath] = entry
            }

            reportProgress(
                progress,
                phase: .indexingFiles,
                completedUnitCount: index + 1,
                totalUnitCount: entries.count,
                unit: .manifestEntries,
                currentItem: entry.filename
            )
        }

        return fileEntriesByPath
    }

    func insertPortableIndexPathAliases(
        _ entries: [WhatsAppBackupEntry],
        in db: Database,
        progress: WABackupProgressHandler? = nil
    ) throws {
        reportProgress(
            progress,
            phase: .indexingPathAliases,
            completedUnitCount: 0,
            totalUnitCount: entries.count,
            unit: .manifestEntries
        )

        for (index, entry) in entries.enumerated() {
            let normalizedPath = normalizedWhatsAppRelativePath(entry.filename)
            try insertPortableIndexPathAlias(
                aliasPath: entry.filename,
                extractedRelativePath: normalizedPath,
                reason: "manifest-relative-path",
                fileID: entry.fileHash,
                in: db
            )

            if entry.filename != normalizedPath {
                try insertPortableIndexPathAlias(
                    aliasPath: normalizedPath,
                    extractedRelativePath: normalizedPath,
                    reason: "normalized-manifest-relative-path",
                    fileID: entry.fileHash,
                    in: db
                )
            }

            try insertPortableIndexPathAlias(
                aliasPath: "/" + normalizedPath,
                extractedRelativePath: normalizedPath,
                reason: "leading-slash-normalization",
                fileID: entry.fileHash,
                in: db
            )

            if normalizedPath.hasPrefix("Message/Media/") {
                let mediaLocalPath = String(normalizedPath.dropFirst("Message/".count))
                try insertPortableIndexPathAlias(
                    aliasPath: mediaLocalPath,
                    extractedRelativePath: normalizedPath,
                    reason: "message-media-local-path",
                    fileID: entry.fileHash,
                    in: db
                )
                try insertPortableIndexPathAlias(
                    aliasPath: "/" + mediaLocalPath,
                    extractedRelativePath: normalizedPath,
                    reason: "message-media-local-path-leading-slash",
                    fileID: entry.fileHash,
                    in: db
                )
            }

            reportProgress(
                progress,
                phase: .indexingPathAliases,
                completedUnitCount: index + 1,
                totalUnitCount: entries.count,
                unit: .manifestEntries,
                currentItem: entry.filename
            )
        }
    }

    func insertPortableIndexPathAlias(
        aliasPath: String,
        extractedRelativePath: String,
        reason: String,
        fileID: String,
        in db: Database
    ) throws {
        let normalizedAliasPath = normalizedWhatsAppRelativePath(aliasPath)
        guard !normalizedAliasPath.isEmpty else {
            return
        }

        try db.execute(
            sql: """
                INSERT OR IGNORE INTO path_aliases (
                    alias_path,
                    normalized_alias_path,
                    extracted_relative_path,
                    reason,
                    file_id
                )
                VALUES (?, ?, ?, ?, ?)
                """,
            arguments: [
                aliasPath,
                normalizedAliasPath,
                extractedRelativePath,
                reason,
                fileID
            ]
        )
    }

    func insertPortableIndexMediaItems(
        fileEntriesByPath: [String: WhatsAppBackupEntry],
        rootURL: URL,
        in db: Database,
        progress: WABackupProgressHandler? = nil
    ) throws {
        let chatStorageURL = rootURL.appendingPathComponent("ChatStorage.sqlite")
        guard FileManager.default.fileExists(atPath: chatStorageURL.path) else {
            try insertPortableIndexMetadataValue(
                "media_items_status",
                "ChatStorage.sqlite not found in extracted backup.",
                in: db
            )
            return
        }

        do {
            let chatStorageQueue = try DatabaseQueue(path: chatStorageURL.path)
            let mediaRows = try chatStorageQueue.read { chatDB in
                try Row.fetchAll(
                    chatDB,
                    sql: """
                    SELECT Z_PK, ZMEDIALOCALPATH FROM ZWAMEDIAITEM
                    WHERE ZMEDIALOCALPATH IS NOT NULL
                      AND ZMEDIALOCALPATH <> ''
                    ORDER BY Z_PK ASC
                    """
                )
            }
            reportProgress(
                progress,
                phase: .indexingMediaItems,
                completedUnitCount: 0,
                totalUnitCount: mediaRows.count,
                unit: .mediaItems
            )

            for (index, row) in mediaRows.enumerated() {
                let mediaItemID = row.value(for: "Z_PK", default: Int64(0))
                guard let localPath: String = row["ZMEDIALOCALPATH"] else {
                    reportProgress(
                        progress,
                        phase: .indexingMediaItems,
                        completedUnitCount: index + 1,
                        totalUnitCount: mediaRows.count,
                        unit: .mediaItems,
                        currentItem: String(mediaItemID)
                    )
                    continue
                }

                let normalizedLocalPath = normalizedWhatsAppRelativePath(localPath)
                let resolvedEntry = resolvePortableIndexMediaEntry(
                    normalizedLocalPath,
                    fileEntriesByPath: fileEntriesByPath
                )
                let status = resolvedEntry == nil ? "missing" : "resolved"
                let resolvedRelativePath = resolvedEntry.map { normalizedWhatsAppRelativePath($0.filename) }

                try db.execute(
                    sql: """
                        INSERT INTO media_items (
                            media_item_id,
                            local_path,
                            normalized_local_path,
                            resolved_relative_path,
                            resolution_status,
                            file_id,
                            manifest_relative_path
                        )
                        VALUES (?, ?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        mediaItemID,
                        localPath,
                        normalizedLocalPath,
                        resolvedRelativePath,
                        status,
                        resolvedEntry?.fileHash,
                        resolvedEntry?.filename
                    ]
                )
                reportProgress(
                    progress,
                    phase: .indexingMediaItems,
                    completedUnitCount: index + 1,
                    totalUnitCount: mediaRows.count,
                    unit: .mediaItems,
                    currentItem: localPath
                )
            }

            try insertPortableIndexMetadataValue("media_items_status", "ok", in: db)
        } catch {
            try insertPortableIndexMetadataValue(
                "media_items_status",
                "Could not read ZWAMEDIAITEM: \(error.localizedDescription)",
                in: db
            )
        }
    }

    func resolvePortableIndexMediaEntry(
        _ normalizedLocalPath: String,
        fileEntriesByPath: [String: WhatsAppBackupEntry]
    ) -> WhatsAppBackupEntry? {
        if let entry = fileEntriesByPath[normalizedLocalPath] {
            return entry
        }

        if normalizedLocalPath.hasPrefix("Media/"),
           !normalizedLocalPath.hasPrefix("Media/Profile/") {
            return fileEntriesByPath["Message/" + normalizedLocalPath]
        }

        return nil
    }

    func insertPortableIndexMetadataValue(_ key: String, _ value: String, in db: Database) throws {
        try db.execute(
            sql: "INSERT OR REPLACE INTO metadata (key, value) VALUES (?, ?)",
            arguments: [key, value]
        )
    }

    func fileByteCount(at url: URL) -> Int64? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber else {
            return nil
        }

        return size.int64Value
    }

    func writeBackupInfo(
        for entries: [WhatsAppBackupEntry],
        rootURL: URL,
        sidecarURL: URL,
        indexURL: URL,
        progress: WABackupProgressHandler? = nil
    ) throws {
        let backupInfo = makeBackupInfo(
            for: entries,
            rootURL: rootURL,
            indexURL: indexURL,
            progress: progress
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data = try encoder.encode(backupInfo)
        let infoURL = sidecarURL.appendingPathComponent("backup-info.json")
        try data.write(to: infoURL, options: .atomic)
    }

    func makeBackupInfo(
        for entries: [WhatsAppBackupEntry],
        rootURL: URL,
        indexURL: URL,
        progress: WABackupProgressHandler? = nil
    ) -> ExtractedWhatsAppBackupInfo {
        var warnings: [String] = []
        let fileEntries = entries.filter { $0.type == .file }
        let directoryEntries = entries.filter { $0.type == .directory }
        let otherEntries = entries.filter { $0.type == .other }

        var copiedFiles = 0
        var missingFiles = 0
        var extractedBytes: Int64 = 0

        reportProgress(
            progress,
            phase: .calculatingBackupInfo,
            completedUnitCount: 0,
            totalUnitCount: fileEntries.count,
            unit: .files,
            currentItem: "backup-info.json"
        )

        for (index, entry) in fileEntries.enumerated() {
            let targetURL = rootURL.appendingPathComponent(normalizedWhatsAppRelativePath(entry.filename))
            guard FileManager.default.fileExists(atPath: targetURL.path) else {
                missingFiles += 1
                reportProgress(
                    progress,
                    phase: .calculatingBackupInfo,
                    completedUnitCount: index + 1,
                    totalUnitCount: fileEntries.count,
                    unit: .files,
                    currentItem: entry.filename
                )
                continue
            }

            copiedFiles += 1
            extractedBytes += fileByteCount(at: targetURL) ?? 0
            reportProgress(
                progress,
                phase: .calculatingBackupInfo,
                completedUnitCount: index + 1,
                totalUnitCount: fileEntries.count,
                unit: .files,
                currentItem: entry.filename
            )
        }

        let mediaItemCounts = readMediaItemCounts(from: indexURL, warnings: &warnings)
        let databaseCounts = readDatabaseCounts(rootURL: rootURL, warnings: &warnings)

        return ExtractedWhatsAppBackupInfo(
            schemaVersion: 1,
            generator: "SwiftWABackupAPI",
            generatedAt: Date(),
            source: ExtractedWhatsAppBackupInfo.Source(
                iPhoneBackupIdentifier: identifier,
                iPhoneBackupCreationDate: creationDate,
                isEncrypted: isEncrypted,
                domain: whatsAppBackupDomain
            ),
            manifestCounts: ExtractedWhatsAppBackupInfo.ManifestCounts(
                totalEntries: entries.count,
                files: fileEntries.count,
                directories: directoryEntries.count,
                otherEntries: otherEntries.count
            ),
            copyCounts: ExtractedWhatsAppBackupInfo.CopyCounts(
                copiedFiles: copiedFiles,
                missingFiles: missingFiles
            ),
            mediaItemCounts: mediaItemCounts,
            databaseCounts: databaseCounts,
            sizes: ExtractedWhatsAppBackupInfo.Sizes(
                extractedBytes: extractedBytes,
                indexBytes: fileByteCount(at: indexURL)
            ),
            warnings: warnings
        )
    }

    func readMediaItemCounts(
        from indexURL: URL,
        warnings: inout [String]
    ) -> ExtractedWhatsAppBackupInfo.MediaItemCounts {
        do {
            let indexQueue = try DatabaseQueue(path: indexURL.path)
            return try indexQueue.read { db in
                let total = try countRowsIfPresent(in: db, table: "media_items") ?? 0
                let resolved = try Int.fetchOne(
                    db,
                    sql: "SELECT COUNT(*) FROM media_items WHERE resolution_status = ?",
                    arguments: ["resolved"]
                ) ?? 0
                let missing = try Int.fetchOne(
                    db,
                    sql: "SELECT COUNT(*) FROM media_items WHERE resolution_status = ?",
                    arguments: ["missing"]
                ) ?? 0

                return ExtractedWhatsAppBackupInfo.MediaItemCounts(
                    total: total,
                    resolved: resolved,
                    missing: missing
                )
            }
        } catch {
            warnings.append("Could not read media item counts from .wa-backup/index.sqlite: \(error.localizedDescription)")
            return ExtractedWhatsAppBackupInfo.MediaItemCounts(total: 0, resolved: 0, missing: 0)
        }
    }

    func readDatabaseCounts(
        rootURL: URL,
        warnings: inout [String]
    ) -> ExtractedWhatsAppBackupInfo.DatabaseCounts {
        var chats: Int?
        var messages: Int?
        var supportedMessages: Int?
        var mediaItems: Int?
        var contacts: Int?
        var lidAccounts: Int?
        var groupMembers: Int?
        var profilePushNames: Int?

        let chatStorageURL = rootURL.appendingPathComponent("ChatStorage.sqlite")
        if FileManager.default.fileExists(atPath: chatStorageURL.path) {
            do {
                let chatStorageQueue = try DatabaseQueue(path: chatStorageURL.path)
                try chatStorageQueue.read { db in
                    chats = try countRowsIfPresent(in: db, table: ChatSession.tableName)
                    messages = try countRowsIfPresent(in: db, table: Message.tableName)
                    supportedMessages = try countSupportedMessagesIfPresent(in: db)
                    mediaItems = try countRowsIfPresent(in: db, table: MediaItem.tableName)
                    groupMembers = try countRowsIfPresent(in: db, table: GroupMember.tableName)
                    profilePushNames = try countRowsIfPresent(in: db, table: ProfilePushName.tableName)
                }
            } catch {
                warnings.append("Could not read ChatStorage.sqlite counts: \(error.localizedDescription)")
            }
        } else {
            warnings.append("ChatStorage.sqlite not found in extracted backup.")
        }

        let contactsURL = rootURL.appendingPathComponent("ContactsV2.sqlite")
        if FileManager.default.fileExists(atPath: contactsURL.path) {
            do {
                let contactsQueue = try DatabaseQueue(path: contactsURL.path)
                try contactsQueue.read { db in
                    contacts = try countRowsIfPresent(in: db, table: AddressBookContact.tableName)
                }
            } catch {
                warnings.append("Could not read ContactsV2.sqlite counts: \(error.localizedDescription)")
            }
        }

        let lidURL = rootURL.appendingPathComponent("LID.sqlite")
        if FileManager.default.fileExists(atPath: lidURL.path) {
            do {
                let lidQueue = try DatabaseQueue(path: lidURL.path)
                try lidQueue.read { db in
                    lidAccounts = try countRowsIfPresent(in: db, table: LidAccount.tableName)
                }
            } catch {
                warnings.append("Could not read LID.sqlite counts: \(error.localizedDescription)")
            }
        }

        return ExtractedWhatsAppBackupInfo.DatabaseCounts(
            chats: chats,
            messages: messages,
            supportedMessages: supportedMessages,
            mediaItems: mediaItems,
            contacts: contacts,
            lidAccounts: lidAccounts,
            groupMembers: groupMembers,
            profilePushNames: profilePushNames
        )
    }

    func countSupportedMessagesIfPresent(in db: Database) throws -> Int? {
        guard try tableExists(Message.tableName, in: db),
              try columnExists("ZMESSAGETYPE", in: Message.tableName, db: db) else {
            return nil
        }

        let placeholders = SupportedMessageType.allValues.count.questionMarks
        return try Int.fetchOne(
            db,
            sql: """
                SELECT COUNT(*)
                FROM \(Message.tableName)
                WHERE ZMESSAGETYPE IN (\(placeholders))
                """,
            arguments: StatementArguments(SupportedMessageType.allValues)
        )
    }

    func countRowsIfPresent(in db: Database, table: String) throws -> Int? {
        guard try tableExists(table, in: db) else {
            return nil
        }

        return try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(table)")
    }

    func tableExists(_ table: String, in db: Database) throws -> Bool {
        let count = try Int.fetchOne(
            db,
            sql: """
                SELECT COUNT(*)
                FROM sqlite_master
                WHERE type = 'table'
                  AND name = ?
                """,
            arguments: [table]
        ) ?? 0

        return count > 0
    }

    func columnExists(_ column: String, in table: String, db: Database) throws -> Bool {
        let columns = try db.columns(in: table).map { $0.name.uppercased() }
        return columns.contains(column.uppercased())
    }

    func writePortableReadme(to sidecarURL: URL) throws {
        let readmeURL = sidecarURL.appendingPathComponent("README.md")
        let contents = """
        # WhatsApp Path Resolution Index

        This directory is generated by SwiftWABackupAPI when a WhatsApp app-group
        backup is extracted from an iPhone backup.

        ## Files

        - `index.sqlite` is a portable SQLite index for this extracted copy.
        - `backup-info.json` is a portable JSON summary with source metadata,
          file counts, byte counts, media resolution counts, and best-effort
          WhatsApp database row counts.
        - Paths stored in the index are relative to the extracted WhatsApp backup
          root, not to the original iPhone backup and not to this `.wa-backup`
          directory.

        ## Why This Exists

        iOS backups store files by hash and describe their original app-relative
        paths in `Manifest.db`. WhatsApp databases may also store local media
        paths such as `Media/...` or `/Media/...`. In extracted copies, many
        message media files live under `Message/Media/...`, while profile media
        lives under `Media/Profile/...`.

        This index documents those relationships so external tools can resolve
        paths without scanning the whole extracted backup and without needing
        SwiftWABackupAPI.

        ## SQLite Tables

        - `metadata`: generator, schema version, source backup identifier, and
          path semantics.
        - `files`: every WhatsApp-domain entry copied or recreated from the
          iPhone backup manifest.
        - `path_aliases`: common path forms that point at the same extracted
          file, including leading-slash normalization and `Media/...` aliases
          for files extracted under `Message/Media/...`.
        - `media_items`: `ZWAMEDIAITEM.ZMEDIALOCALPATH` values from
          `ChatStorage.sqlite`, with the resolved extracted relative path when
          one can be found.

        ## Resolution Rules

        1. Normalize path separators to `/` and remove leading `/` components.
        2. Try the normalized path directly under the extracted backup root.
        3. If the normalized path starts with `Media/` but not `Media/Profile/`,
           also try `Message/` plus the normalized path.
        4. For profile and contact photos, look under `Media/Profile/`.

        Example:

        ```text
        ZWAMEDIAITEM.ZMEDIALOCALPATH = /Media/123@s.whatsapp.net/a/b/file.jpg
        extracted relative path      = Message/Media/123@s.whatsapp.net/a/b/file.jpg
        ```

        """

        try Data(contents.utf8).write(to: readmeURL, options: .atomic)
    }
}

private func normalizedWhatsAppRelativePath(_ relativePath: String) -> String {
    relativePath
        .replacingOccurrences(of: "\\", with: "/")
        .split(separator: "/", omittingEmptySubsequences: true)
        .joined(separator: "/")
}

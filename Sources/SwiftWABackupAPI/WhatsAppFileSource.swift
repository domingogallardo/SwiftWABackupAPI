//
//  WhatsAppFileSource.swift
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
    }

    let filename: String
    let fileHash: String
    let type: EntryType
}

protocol WhatsAppFileSource {
    func urlForWhatsAppFile(endsWith relativePath: String) throws -> URL
    func whatsAppFileDetails(containing relativePath: String) throws -> [WhatsAppFileDetails]
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

extension ExtractedWhatsAppBackup: WhatsAppFileSource {
    func urlForWhatsAppFile(endsWith relativePath: String) throws -> URL {
        let normalizedPath = normalizedWhatsAppRelativePath(relativePath)
        let directURL = url.appendingPathComponent(normalizedPath)

        if FileManager.default.fileExists(atPath: directURL.path) {
            return directURL
        }

        let suffix = "/" + normalizedPath
        if let match = try enumerateFiles().first(where: { $0.filename == normalizedPath || $0.filename.hasSuffix(suffix) }) {
            return match.sourceURL
        }

        throw DomainError.mediaNotFound(path: relativePath)
    }

    func whatsAppFileDetails(containing relativePath: String) throws -> [WhatsAppFileDetails] {
        let normalizedPath = normalizedWhatsAppRelativePath(relativePath)
        let files = try enumerateFiles()

        guard !normalizedPath.isEmpty else {
            return files
        }

        return files.filter { $0.filename.contains(normalizedPath) }
    }

    private func enumerateFiles() throws -> [WhatsAppFileDetails] {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: []
        ) else {
            throw BackupError.invalidBackup(url: url, reason: "Extracted WhatsApp directory could not be enumerated.")
        }

        let rootPath = url.standardizedFileURL.path
        var files: [WhatsAppFileDetails] = []

        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else {
                continue
            }

            let filePath = fileURL.standardizedFileURL.path
            guard filePath.hasPrefix(rootPath + "/") else {
                continue
            }

            let relativePath = String(filePath.dropFirst(rootPath.count + 1))
            files.append(WhatsAppFileDetails(filename: relativePath, sourceURL: fileURL))
        }

        return files
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
        overwriteExisting: Bool = false
    ) throws -> ExtractedWhatsAppBackup {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)

        for entry in try fetchAllWhatsAppBackupEntries() {
            let targetURL = try extractedTargetURL(
                forWhatsAppRelativePath: entry.filename,
                under: destinationDirectory
            )

            switch entry.type {
            case .directory:
                try fileManager.createDirectory(at: targetURL, withIntermediateDirectories: true)
                continue

            case .other:
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
        }

        return ExtractedWhatsAppBackup(url: destinationDirectory)
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
}

private func normalizedWhatsAppRelativePath(_ relativePath: String) -> String {
    relativePath
        .replacingOccurrences(of: "\\", with: "/")
        .split(separator: "/", omittingEmptySubsequences: true)
        .joined(separator: "/")
}

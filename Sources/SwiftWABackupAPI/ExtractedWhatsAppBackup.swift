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
        let normalizedPath = normalizedWhatsAppRelativePath(relativePath)

        for candidate in directFileURLCandidates(for: normalizedPath) {
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }

        throw DomainError.mediaNotFound(path: relativePath)
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

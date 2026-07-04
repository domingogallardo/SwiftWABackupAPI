//
//  MediaCopier.swift
//  SwiftWABackupAPI
//
//  Created by Domingo Gallardo on 17/4/25.

//  Encapsulates file-copy logic so it can be reused from WABackup.
//

import Foundation

struct MediaCopier {
    weak var delegate: WABackupDelegate?

    /// Copies a WhatsApp file into the destination directory when one is provided.
    /// If the target already exists, the copy is skipped.
    /// The delegate is notified whenever the file is processed.
    @discardableResult
    func copy(sourceURL: URL,
              named fileName: String,
              to directoryURL: URL?,
              progress: WABackupProgressHandler? = nil) throws -> String {

        if let dir = directoryURL {
            let targetURL = dir.appendingPathComponent(fileName)
            try copyIfNeeded(from: sourceURL, to: targetURL)
        }

        delegate?.didWriteMediaFile(fileName: fileName)
        reportProgress(
            progress,
            phase: .exportingMedia,
            completedUnitCount: 1,
            unit: .mediaFiles,
            currentItem: fileName
        )
        return fileName
    }

    // MARK: - Private
    private func copyIfNeeded(from sourceURL: URL, to targetURL: URL) throws {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: targetURL.path) else { return }

        do {
            try fm.copyItem(at: sourceURL, to: targetURL)
        } catch {
            throw BackupError.fileCopy(
                source: sourceURL,
                destination: targetURL,
                underlying: error
            )
        }
    }
}

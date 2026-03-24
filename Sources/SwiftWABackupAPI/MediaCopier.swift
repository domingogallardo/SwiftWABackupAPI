//
//  MediaCopier.swift
//  SwiftWABackupAPI
//
//  Created by Domingo Gallardo on 17/4/25.

//  Encapsulates file-copy logic so it can be reused from WABackup.
//

import Foundation

struct MediaCopier {
    let backup: IPhoneBackup
    weak var delegate: WABackupDelegate?

    /// Copies a hashed backup file into the destination directory when one is provided.
    /// If the target already exists, the copy is skipped.
    /// The delegate is notified whenever the file is processed.
    @discardableResult
    func copy(hash: String,
              named fileName: String,
              to directoryURL: URL?) throws -> String {

        if let dir = directoryURL {
            let targetURL = dir.appendingPathComponent(fileName)
            try copyIfNeeded(hashFile: hash, to: targetURL)
        }

        delegate?.didWriteMediaFile(fileName: fileName)
        return fileName
    }

    // MARK: - Private
    private func copyIfNeeded(hashFile: String, to targetURL: URL) throws {
        let sourceURL = backup.getUrl(fileHash: hashFile)
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

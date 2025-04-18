//
//  MediaCopier.swift
//  SwiftWABackupAPI
//
//  Created by Domingo Gallardo on 17/4/25.

//  Encapsulates all file‑copy logic so it can be reused from WABackup.
//

import Foundation

struct MediaCopier {
    let backup: IPhoneBackup
    weak var delegate: WABackupDelegate?

    /// Copia el hash del backup al directorio destino (si se indica) y devuelve el nombre del fichero.
    /// ‑ Si el fichero ya existe, no hace nada.
    /// ‑ Notifica al delegate siempre que el fichero haya sido «procesado».
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

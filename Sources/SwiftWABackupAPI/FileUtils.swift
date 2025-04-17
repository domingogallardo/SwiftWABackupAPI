//
//  FileUtils.swift
//  SwiftWABackupAPI
//
//  Created by Domingo Gallardo on 17/4/25.
//
//  Utility namespace for operations on filenames and iPhone‑backup hashes
//

import Foundation

/// Agrupa helpers relacionados con ficheros de WhatsApp dentro del backup.
enum FileUtils {
    public typealias NameHash = FilenameAndHash      // (filename, fileHash)

    /// Devuelve el fichero más reciente cuyo nombre empieza por `prefixFilename`
    /// y tiene la extensión indicada (`jpg`, `thumb`, …).
    static func latestFile(for prefixFilename: String,
                           fileExtension: String,
                           in files: [NameHash]) -> NameHash? {

        var latest: NameHash?
        var latestTimestamp = 0

        for item in files {
            if let ts = extractTimeSuffix(from: prefixFilename,
                                          fileExtension: fileExtension,
                                          fileName: item.filename),
               ts > latestTimestamp {
                latestTimestamp = ts
                latest = item
            }
        }
        return latest
    }

    /// Extrae el sufijo entero que WhatsApp añade a las fotos de perfil
    /// (`Media/Profile/<JID>-<timestamp>.jpg`).
    static func extractTimeSuffix(from prefixFilename: String,
                                  fileExtension: String,
                                  fileName: String) -> Int? {

        let pattern = prefixFilename + "-(\\d+)\\." + fileExtension
        guard let regex  = try? NSRegularExpression(pattern: pattern) else { return nil }

        let range   = NSRange(fileName.startIndex..<fileName.endIndex, in: fileName)
        guard let m = regex.firstMatch(in: fileName, range: range) else { return nil }

        let suffix  = (fileName as NSString).substring(with: m.range(at: 1))
        return Int(suffix)
    }
}

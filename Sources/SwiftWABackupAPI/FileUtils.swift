//
//  FileUtils.swift
//  SwiftWABackupAPI
//
//  Created by Domingo Gallardo on 17/4/25.
//
//  Utility namespace for operations on filenames and iPhone‑backup hashes
//

import Foundation

/// Groups helpers related to WhatsApp files stored inside an iPhone backup.
enum FileUtils {
    typealias NameHash = FilenameAndHash

    /// Returns the newest file whose name starts with `prefixFilename`
    /// and ends with the provided extension (`jpg`, `thumb`, and so on).
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

    static func latestFile(for prefixFilename: String,
                           fileExtension: String,
                           in files: [WhatsAppFileDetails]) -> WhatsAppFileDetails? {

        var latest: WhatsAppFileDetails?
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

    /// Extracts the last timestamp suffix used by WhatsApp profile photos.
    ///
    /// WhatsApp stores both `<JID>-<timestamp>.<extension>` and
    /// `<JID>-<timestamp>-<timestamp>.<extension>` variants.
    static func extractTimeSuffix(from prefixFilename: String,
                                  fileExtension: String,
                                  fileName: String) -> Int? {

        let escapedPrefix = NSRegularExpression.escapedPattern(for: prefixFilename)
        let escapedExtension = NSRegularExpression.escapedPattern(for: fileExtension)
        let pattern = "^" + escapedPrefix + "-(?:\\d+-)*(\\d+)\\." + escapedExtension + "$"
        guard let regex  = try? NSRegularExpression(pattern: pattern) else { return nil }

        let range   = NSRange(fileName.startIndex..<fileName.endIndex, in: fileName)
        guard let m = regex.firstMatch(in: fileName, range: range) else { return nil }

        let suffix  = (fileName as NSString).substring(with: m.range(at: 1))
        return Int(suffix)
    }
}

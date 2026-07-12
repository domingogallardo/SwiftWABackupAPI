//
//  MediaReference.swift
//  SwiftWABackupAPI
//

import Foundation

/// Portable metadata that identifies a file inside an extracted WhatsApp backup.
public struct MediaReference: Codable, Equatable, Hashable {
    /// Path relative to the root of the extracted WhatsApp backup.
    public let relativePath: String

    /// Last path component of the referenced file.
    public let filename: String

    /// File size in bytes when it can be read from disk.
    public let byteCount: Int64?

    /// Best-effort MIME type inferred from the filename extension.
    public let mimeType: String?

    public init(
        relativePath: String,
        filename: String,
        byteCount: Int64? = nil,
        mimeType: String? = nil
    ) {
        self.relativePath = relativePath
        self.filename = filename
        self.byteCount = byteCount
        self.mimeType = mimeType
    }
}

extension MediaReference {
    static func inferredMIMEType(for filename: String) -> String? {
        switch URL(fileURLWithPath: filename).pathExtension.lowercased() {
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "heic": return "image/heic"
        case "heif": return "image/heif"
        case "thumb": return "image/jpeg"
        case "mp4", "m4v": return "video/mp4"
        case "mov": return "video/quicktime"
        case "3gp": return "video/3gpp"
        case "mp3": return "audio/mpeg"
        case "m4a": return "audio/mp4"
        case "aac": return "audio/aac"
        case "ogg", "opus": return "audio/ogg"
        case "wav": return "audio/wav"
        case "pdf": return "application/pdf"
        case "txt": return "text/plain"
        case "csv": return "text/csv"
        case "vcf": return "text/vcard"
        case "json": return "application/json"
        case "zip": return "application/zip"
        case "doc": return "application/msword"
        case "docx": return "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        case "xls": return "application/vnd.ms-excel"
        case "xlsx": return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        case "ppt": return "application/vnd.ms-powerpoint"
        case "pptx": return "application/vnd.openxmlformats-officedocument.presentationml.presentation"
        default: return nil
        }
    }
}

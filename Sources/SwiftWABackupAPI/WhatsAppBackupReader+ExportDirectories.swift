//
//  WhatsAppBackupReader+ExportDirectories.swift
//  SwiftWABackupAPI
//

import Foundation

extension WhatsAppBackupReader {
    func chatProfilePhotosDirectory(override: URL?) throws -> URL? {
        if let override {
            return override
        }

        guard let exportRootDirectory else {
            return nil
        }

        let directory = exportRootDirectory.appendingPathComponent("ChatProfilePhotos", isDirectory: true)
        try createExportDirectory(directory)
        return directory
    }

    func chatMediaDirectory(chatId: Int, override: URL?) throws -> URL? {
        if let override {
            return override
        }

        guard let exportRootDirectory else {
            return nil
        }

        let directory = exportRootDirectory
            .appendingPathComponent("Chats", isDirectory: true)
            .appendingPathComponent(String(chatId), isDirectory: true)
            .appendingPathComponent("Media", isDirectory: true)
        try createExportDirectory(directory)
        return directory
    }

    private func createExportDirectory(_ directory: URL) throws {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw BackupError.directoryAccess(error)
        }
    }
}

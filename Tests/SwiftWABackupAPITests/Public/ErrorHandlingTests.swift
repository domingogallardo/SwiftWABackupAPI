import Foundation
import XCTest
@testable import SwiftWABackupAPI

final class ErrorHandlingTests: XCTestCase {
    func testGetBackupsThrowsForMissingRootDirectory() {
        let waBackup = WABackup(iPhoneBackupsPath: "/tmp/SwiftWABackupAPI/non-existent-\(UUID().uuidString)")

        XCTAssertThrowsError(try waBackup.getBackups()) { error in
            guard case BackupError.directoryAccess = error else {
                return XCTFail("Expected BackupError.directoryAccess, got \(error)")
            }
        }
    }

    func testGetBackupsReportsIncompleteBackupAsInvalid() throws {
        let rootURL = try PublicTestSupport.makeTemporaryDirectory(prefix: "SwiftWABackupAPI-invalid-backup")
        defer { try? PublicTestSupport.removeItemIfExists(at: rootURL) }

        let backupURL = rootURL.appendingPathComponent("incomplete-backup", isDirectory: true)
        try FileManager.default.createDirectory(at: backupURL, withIntermediateDirectories: true)
        try Data().write(to: backupURL.appendingPathComponent("Info.plist"))

        let waBackup = WABackup(iPhoneBackupsPath: rootURL.path)
        let backups = try waBackup.getBackups()

        XCTAssertTrue(backups.validBackups.isEmpty)
        XCTAssertEqual(
            backups.invalidBackups.map { $0.standardizedFileURL.path },
            [backupURL.standardizedFileURL.path]
        )
    }

    func testInspectBackupsReportsIncompleteBackupDetails() throws {
        let rootURL = try PublicTestSupport.makeTemporaryDirectory(prefix: "SwiftWABackupAPI-invalid-backup-diagnostics")
        defer { try? PublicTestSupport.removeItemIfExists(at: rootURL) }

        let backupURL = rootURL.appendingPathComponent("incomplete-backup", isDirectory: true)
        try FileManager.default.createDirectory(at: backupURL, withIntermediateDirectories: true)
        try Data().write(to: backupURL.appendingPathComponent("Info.plist"))

        let waBackup = WABackup(iPhoneBackupsPath: rootURL.path)
        let infos = try waBackup.inspectBackups()
        let info = try XCTUnwrap(infos.first)

        XCTAssertEqual(info.identifier, "incomplete-backup")
        XCTAssertEqual(info.status, .missingRequiredFile)
        XCTAssertFalse(info.isReady)
        XCTAssertEqual(info.issue, "Manifest.db is missing.")
        XCTAssertNil(info.backup)
    }

    func testGetChatsFailsWhenDatabaseIsNotConnected() {
        let waBackup = WABackup(iPhoneBackupsPath: FileManager.default.temporaryDirectory.path)

        XCTAssertThrowsError(try waBackup.getChats()) { error in
            guard case DatabaseErrorWA.connection = error else {
                return XCTFail("Expected DatabaseErrorWA.connection, got \(error)")
            }
        }
    }

    func testGetChatFailsWhenDatabaseIsNotConnected() {
        let waBackup = WABackup(iPhoneBackupsPath: FileManager.default.temporaryDirectory.path)

        XCTAssertThrowsError(try waBackup.getChat(chatId: 44, directoryToSaveMedia: nil)) { error in
            guard case DatabaseErrorWA.connection = error else {
                return XCTFail("Expected DatabaseErrorWA.connection, got \(error)")
            }
        }
    }

    func testOpeningExtractedBackupRejectsUnsupportedSchema() throws {
        let fixture = try PublicTestSupport.makeTemporaryBackup { db in
            try db.execute(sql: "CREATE TABLE NotWhatsApp (id INTEGER PRIMARY KEY)")
        }
        defer { try? PublicTestSupport.removeItemIfExists(at: fixture.rootURL) }

        let extractedBackup = try PublicTestSupport.extractWhatsAppBackup(from: fixture)

        XCTAssertThrowsError(try WABackup(whatsAppBackupAt: extractedBackup.url)) { error in
            guard case DatabaseErrorWA.unsupportedSchema = error else {
                return XCTFail("Expected DatabaseErrorWA.unsupportedSchema, got \(error)")
            }
        }
    }

    func testFetchWAFileHashThrowsWhenMediaIsMissing() throws {
        let fixture = try PublicTestSupport.makeTemporaryBackup { _ in }
        defer { try? PublicTestSupport.removeItemIfExists(at: fixture.rootURL) }

        XCTAssertThrowsError(try fixture.backup.fetchWAFileHash(endsWith: "Media/DefinitelyMissing/nope.bin")) { error in
            guard case DatabaseErrorWA.connection(let underlying) = error else {
                return XCTFail("Expected DatabaseErrorWA.connection, got \(error)")
            }

            guard case DomainError.mediaNotFound(let path) = underlying else {
                return XCTFail("Expected underlying DomainError.mediaNotFound, got \(underlying)")
            }

            XCTAssertEqual(path, "Media/DefinitelyMissing/nope.bin")
        }
    }
}

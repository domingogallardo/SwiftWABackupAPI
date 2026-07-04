import Foundation
import XCTest
@testable import SwiftWABackupAPI

final class ErrorHandlingTests: XCTestCase {
    func testGetIPhoneBackupsThrowsForMissingRootDirectory() {
        let manager = IPhoneBackupManager(iPhoneBackupsPath: "/tmp/SwiftWABackupAPI/non-existent-\(UUID().uuidString)")

        XCTAssertThrowsError(try manager.getIPhoneBackups()) { error in
            guard case BackupError.directoryAccess = error else {
                return XCTFail("Expected BackupError.directoryAccess, got \(error)")
            }
        }
    }

    func testGetIPhoneBackupsIgnoresIncompleteBackup() throws {
        let rootURL = try PublicTestSupport.makeTemporaryDirectory(prefix: "SwiftWABackupAPI-invalid-backup")
        defer { try? PublicTestSupport.removeItemIfExists(at: rootURL) }

        let backupURL = rootURL.appendingPathComponent("incomplete-backup", isDirectory: true)
        try FileManager.default.createDirectory(at: backupURL, withIntermediateDirectories: true)
        try Data().write(to: backupURL.appendingPathComponent("Info.plist"))

        let manager = IPhoneBackupManager(iPhoneBackupsPath: rootURL.path)
        let backups = try manager.getIPhoneBackups()

        XCTAssertTrue(backups.isEmpty)
    }

    func testInspectIPhoneBackupsReportsIncompleteBackupDetails() throws {
        let rootURL = try PublicTestSupport.makeTemporaryDirectory(prefix: "SwiftWABackupAPI-invalid-backup-diagnostics")
        defer { try? PublicTestSupport.removeItemIfExists(at: rootURL) }

        let backupURL = rootURL.appendingPathComponent("incomplete-backup", isDirectory: true)
        try FileManager.default.createDirectory(at: backupURL, withIntermediateDirectories: true)
        try Data().write(to: backupURL.appendingPathComponent("Info.plist"))

        let manager = IPhoneBackupManager(iPhoneBackupsPath: rootURL.path)
        let infos = try manager.inspectIPhoneBackups()
        let info = try XCTUnwrap(infos.first)

        XCTAssertEqual(info.identifier, "incomplete-backup")
        XCTAssertEqual(info.status, .missingRequiredFile)
        XCTAssertFalse(info.isReady)
        XCTAssertEqual(info.issue, "Manifest.db is missing.")
        XCTAssertNil(info.iPhoneBackup)
    }

    func testOpeningExtractedBackupFailsWhenChatStorageIsMissing() throws {
        let rootURL = try PublicTestSupport.makeTemporaryDirectory(prefix: "SwiftWABackupAPI-missing-chatstorage")
        defer { try? PublicTestSupport.removeItemIfExists(at: rootURL) }

        XCTAssertThrowsError(try ExtractedWhatsAppBackup(url: rootURL).openReader()) { error in
            guard case DomainError.mediaNotFound(let path) = error else {
                return XCTFail("Expected DomainError.mediaNotFound, got \(error)")
            }
            XCTAssertEqual(path, "ChatStorage.sqlite")
        }
    }

    func testOpeningExtractedBackupFailsWhenPathIsMissing() {
        let backup = ExtractedWhatsAppBackup(
            path: "/tmp/SwiftWABackupAPI/non-existent-whatsapp-\(UUID().uuidString)"
        )

        XCTAssertThrowsError(try backup.openReader()) { error in
            guard case DomainError.mediaNotFound(let path) = error else {
                return XCTFail("Expected DomainError.mediaNotFound, got \(error)")
            }
            XCTAssertEqual(path, "ChatStorage.sqlite")
        }
    }

    func testOpeningExtractedBackupRejectsUnsupportedSchema() throws {
        let fixture = try PublicTestSupport.makeTemporaryBackup { db in
            try db.execute(sql: "CREATE TABLE NotWhatsApp (id INTEGER PRIMARY KEY)")
        }
        defer { try? PublicTestSupport.removeItemIfExists(at: fixture.rootURL) }

        let extractedBackup = try PublicTestSupport.extractWhatsAppBackup(from: fixture)

        XCTAssertThrowsError(try extractedBackup.openReader()) { error in
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

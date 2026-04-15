import Foundation
import XCTest
@testable import SwiftWABackupCLI

final class CLICommandParserTests: XCTestCase {
    func testHelpWithoutArguments() throws {
        let exitCode = runCLI(arguments: [])

        XCTAssertEqual(exitCode.code, 0)
        XCTAssertTrue(exitCode.standardOutput.contains("Usage: SwiftWABackupCLI <command> [options]"))
    }

    func testListBackupsJSON() throws {
        let fixture = try PublicTestSupport.makeSampleBackup()
        defer { try? PublicTestSupport.removeItemIfExists(at: fixture.rootURL) }

        let result = runCLI(arguments: [
            "list-backups",
            "--backup-path", fixture.rootURL.path,
            "--json"
        ])

        XCTAssertEqual(result.code, 0)

        let data = try XCTUnwrap(result.standardOutput.data(using: .utf8))
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let backups = try XCTUnwrap(object?["backups"] as? [[String: Any]])
        let validBackups = try XCTUnwrap(object?["validBackups"] as? [[String: Any]])

        XCTAssertEqual(backups.count, 1)
        XCTAssertEqual(backups.first?["status"] as? String, "ready")
        XCTAssertEqual(backups.first?["isEncrypted"] as? Bool, false)
        XCTAssertEqual(validBackups.count, 1)
        XCTAssertEqual(validBackups.first?["identifier"] as? String, fixture.backup.identifier)
        XCTAssertEqual(validBackups.first?["isEncrypted"] as? Bool, false)
    }

    func testListBackupsJSONReportsEncryptedBackup() throws {
        let fixture = try PublicTestSupport.makeTemporaryBackup(name: "encrypted-backup", isEncrypted: true) { _ in }
        defer { try? PublicTestSupport.removeItemIfExists(at: fixture.rootURL) }

        let result = runCLI(arguments: [
            "list-backups",
            "--backup-path", fixture.rootURL.path,
            "--json"
        ])

        XCTAssertEqual(result.code, 0)

        let data = try XCTUnwrap(result.standardOutput.data(using: .utf8))
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let backups = try XCTUnwrap(object?["backups"] as? [[String: Any]])
        let validBackups = try XCTUnwrap(object?["validBackups"] as? [[String: Any]])

        XCTAssertEqual(backups.count, 1)
        XCTAssertEqual(backups.first?["status"] as? String, "encrypted")
        XCTAssertEqual(backups.first?["isEncrypted"] as? Bool, true)
        XCTAssertEqual(validBackups.count, 1)
        XCTAssertEqual(validBackups.first?["isEncrypted"] as? Bool, true)
    }

    func testListChatsJSONUsesFirstValidBackupByDefault() throws {
        let (waBackup, fixture) = try PublicTestSupport.makeConnectedSampleBackup()
        _ = waBackup
        defer { try? PublicTestSupport.removeItemIfExists(at: fixture.rootURL) }

        let result = runCLI(arguments: [
            "list-chats",
            "--backup-path", fixture.rootURL.path,
            "--json"
        ])

        XCTAssertEqual(result.code, 0)

        let data = try XCTUnwrap(result.standardOutput.data(using: .utf8))
        let chats = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]

        XCTAssertEqual(chats?.count, 2)
        XCTAssertEqual(chats?.first?["id"] as? Int, 44)
    }

    func testListChatsRejectsEncryptedBackupById() throws {
        let fixture = try PublicTestSupport.makeTemporaryBackup(name: "encrypted-backup", isEncrypted: true) { _ in }
        defer { try? PublicTestSupport.removeItemIfExists(at: fixture.rootURL) }

        let result = runCLI(arguments: [
            "list-chats",
            "--backup-path", fixture.rootURL.path,
            "--backup-id", fixture.backup.identifier,
            "--json"
        ])

        XCTAssertEqual(result.code, 1)
        XCTAssertTrue(result.standardError.contains("is not ready for chat access"))
        XCTAssertTrue(result.standardError.contains("Backup is encrypted."))
    }

    func testExportChatWritesOnlyJSONToOutputJSON() throws {
        let fixture = try PublicTestSupport.makeSampleBackup()
        defer { try? PublicTestSupport.removeItemIfExists(at: fixture.rootURL) }

        let outputDirectory = try PublicTestSupport.makeTemporaryDirectory(prefix: "SwiftWABackupAPI-cli-output")
        defer { try? PublicTestSupport.removeItemIfExists(at: outputDirectory) }

        let outputFile = outputDirectory.appendingPathComponent("chat-44.json")

        let result = runCLI(arguments: [
            "export-chat",
            "--backup-path", fixture.rootURL.path,
            "--chat-id", "44",
            "--output-json", outputFile.path,
            "--pretty"
        ])

        XCTAssertEqual(result.code, 0)
        XCTAssertTrue(result.standardOutput.contains("Wrote chat 44"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputFile.path))
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: outputDirectory.appendingPathComponent("fea35851-6a2c-45a3-a784-003d25576b45.pdf").path
            )
        )
    }

    func testExportChatWritesDirectoryBundleToOutputDir() throws {
        let fixture = try PublicTestSupport.makeSampleBackup()
        defer { try? PublicTestSupport.removeItemIfExists(at: fixture.rootURL) }

        let temporaryRoot = try PublicTestSupport.makeTemporaryDirectory(prefix: "SwiftWABackupAPI-cli-output-dir")
        defer { try? PublicTestSupport.removeItemIfExists(at: temporaryRoot) }
        let outputDirectory = temporaryRoot.appendingPathComponent("chat-export", isDirectory: true)

        let result = runCLI(arguments: [
            "export-chat",
            "--backup-path", fixture.rootURL.path,
            "--chat-id", "44",
            "--output-dir", outputDirectory.path,
            "--pretty"
        ])

        let expectedFile = outputDirectory.appendingPathComponent("chat-44.json")

        XCTAssertEqual(result.code, 0)
        XCTAssertTrue(result.standardOutput.contains(expectedFile.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: expectedFile.path))
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: outputDirectory.appendingPathComponent("fea35851-6a2c-45a3-a784-003d25576b45.pdf").path
            )
        )
    }

    func testExportChatRejectsBothOutputModesAtOnce() throws {
        let result = runCLI(arguments: [
            "export-chat",
            "--chat-id", "44",
            "--output-json", "/tmp/chat.json",
            "--output-dir", "/tmp/chat-export"
        ])

        XCTAssertEqual(result.code, 1)
        XCTAssertTrue(result.standardError.contains("Use either --output-json or --output-dir, but not both."))
    }

    func testUnknownCommandReturnsError() throws {
        let result = runCLI(arguments: ["wat"])

        XCTAssertEqual(result.code, 1)
        XCTAssertTrue(result.standardError.contains("Unknown command 'wat'."))
    }

    private func runCLI(arguments: [String]) -> (code: Int32, standardOutput: String, standardError: String) {
        var standardOutput: [String] = []
        var standardError: [String] = []

        let application = CLIApplication()
        let code = application.run(
            arguments: arguments,
            standardOutput: { standardOutput.append($0) },
            standardError: { standardError.append($0) }
        )

        return (
            code,
            standardOutput.joined(separator: "\n"),
            standardError.joined(separator: "\n")
        )
    }
}

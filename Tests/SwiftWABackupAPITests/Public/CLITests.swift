import Foundation
import XCTest
@testable import SwiftWABackupAPI
@testable import SwiftWABackupCLI

final class CLICommandParserTests: XCTestCase {
    func testHelpWithoutArguments() throws {
        let exitCode = runCLI(arguments: [])

        XCTAssertEqual(exitCode.code, 0)
        XCTAssertTrue(exitCode.standardOutput.contains("Usage: SwiftWABackupCLI <command> [options]"))
    }

    func testListIPhoneBackupsJSON() throws {
        let fixture = try PublicTestSupport.makeSampleBackup()
        defer { try? PublicTestSupport.removeItemIfExists(at: fixture.rootURL) }

        let result = runCLI(arguments: [
            "list-iphone-backups",
            "--iphone-backups-path", fixture.rootURL.path,
            "--json"
        ])

        XCTAssertEqual(result.code, 0)

        let data = try XCTUnwrap(result.standardOutput.data(using: .utf8))
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let iPhoneBackups = try XCTUnwrap(object?["iPhoneBackups"] as? [[String: Any]])

        XCTAssertEqual(iPhoneBackups.count, 1)
        XCTAssertEqual(iPhoneBackups.first?["identifier"] as? String, fixture.backup.identifier)
        XCTAssertEqual(iPhoneBackups.first?["status"] as? String, "ready")
        XCTAssertEqual(iPhoneBackups.first?["isEncrypted"] as? Bool, false)
    }

    func testListIPhoneBackupsJSONReportsEncryptedBackup() throws {
        let fixture = try PublicTestSupport.makeTemporaryBackup(name: "encrypted-backup", isEncrypted: true) { _ in }
        defer { try? PublicTestSupport.removeItemIfExists(at: fixture.rootURL) }

        let result = runCLI(arguments: [
            "list-iphone-backups",
            "--iphone-backups-path", fixture.rootURL.path,
            "--json"
        ])

        XCTAssertEqual(result.code, 0)

        let data = try XCTUnwrap(result.standardOutput.data(using: .utf8))
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let iPhoneBackups = try XCTUnwrap(object?["iPhoneBackups"] as? [[String: Any]])

        XCTAssertEqual(iPhoneBackups.count, 1)
        XCTAssertEqual(iPhoneBackups.first?["status"] as? String, "encrypted")
        XCTAssertEqual(iPhoneBackups.first?["isEncrypted"] as? Bool, true)
    }

    func testListChatsRequiresWhatsAppBackupPath() throws {
        let result = runCLI(arguments: [
            "list-chats",
            "--json"
        ])

        XCTAssertEqual(result.code, 1)
        XCTAssertTrue(result.standardError.contains("Missing required argument --whatsapp-backup-path."))
    }

    func testListChatsJSONUsesWhatsAppBackupPath() throws {
        let fixture = try PublicTestSupport.makeSampleBackup()
        defer { try? PublicTestSupport.removeItemIfExists(at: fixture.rootURL) }

        let temporaryRoot = try PublicTestSupport.makeTemporaryDirectory(prefix: "SwiftWABackupAPI-cli-list-extracted")
        defer { try? PublicTestSupport.removeItemIfExists(at: temporaryRoot) }
        let extractedDirectory = temporaryRoot.appendingPathComponent("WhatsApp", isDirectory: true)

        let extractResult = runCLI(arguments: [
            "extract-whatsapp-backup",
            "--iphone-backups-path", fixture.rootURL.path,
            "--output-dir", extractedDirectory.path
        ])
        XCTAssertEqual(extractResult.code, 0)

        let result = runCLI(arguments: [
            "list-chats",
            "--whatsapp-backup-path", extractedDirectory.path,
            "--json"
        ])

        XCTAssertEqual(result.code, 0)

        let data = try XCTUnwrap(result.standardOutput.data(using: .utf8))
        let chats = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]

        XCTAssertEqual(chats?.count, 2)
        XCTAssertEqual(chats?.first?["id"] as? Int, 44)
    }

    func testBackupInfoOutputsGeneratedSummaryJSON() throws {
        let fixture = try PublicTestSupport.makeSampleBackup()
        defer { try? PublicTestSupport.removeItemIfExists(at: fixture.rootURL) }
        let extractedBackup = try PublicTestSupport.extractWhatsAppBackup(from: fixture)

        let result = runCLI(arguments: [
            "backup-info",
            "--whatsapp-backup-path", extractedBackup.path,
            "--pretty"
        ])

        XCTAssertEqual(result.code, 0)

        let data = try XCTUnwrap(result.standardOutput.data(using: .utf8))
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let source = try XCTUnwrap(object?["source"] as? [String: Any])
        let copyCounts = try XCTUnwrap(object?["copyCounts"] as? [String: Any])
        let databaseCounts = try XCTUnwrap(object?["databaseCounts"] as? [String: Any])

        XCTAssertEqual(object?["schemaVersion"] as? Int, 1)
        XCTAssertEqual(source["iPhoneBackupIdentifier"] as? String, fixture.backup.identifier)
        XCTAssertEqual(copyCounts["missingFiles"] as? Int, 0)
        XCTAssertEqual(databaseCounts["chats"] as? Int, 2)
        XCTAssertEqual(databaseCounts["messages"] as? Int, 5)
    }

    func testExportChatWritesOnlyJSONToOutputJSON() throws {
        let fixture = try PublicTestSupport.makeSampleBackup()
        defer { try? PublicTestSupport.removeItemIfExists(at: fixture.rootURL) }
        let extractedBackup = try PublicTestSupport.extractWhatsAppBackup(from: fixture)

        let outputDirectory = try PublicTestSupport.makeTemporaryDirectory(prefix: "SwiftWABackupAPI-cli-output")
        defer { try? PublicTestSupport.removeItemIfExists(at: outputDirectory) }

        let outputFile = outputDirectory.appendingPathComponent("chat-44.json")

        let result = runCLI(arguments: [
            "export-chat",
            "--whatsapp-backup-path", extractedBackup.path,
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
        let extractedBackup = try PublicTestSupport.extractWhatsAppBackup(from: fixture)

        let temporaryRoot = try PublicTestSupport.makeTemporaryDirectory(prefix: "SwiftWABackupAPI-cli-output-dir")
        defer { try? PublicTestSupport.removeItemIfExists(at: temporaryRoot) }
        let outputDirectory = temporaryRoot.appendingPathComponent("chat-export", isDirectory: true)

        let result = runCLI(arguments: [
            "export-chat",
            "--whatsapp-backup-path", extractedBackup.path,
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

    func testExportChatUsesWhatsAppBackupPath() throws {
        let fixture = try PublicTestSupport.makeSampleBackup()
        defer { try? PublicTestSupport.removeItemIfExists(at: fixture.rootURL) }

        let temporaryRoot = try PublicTestSupport.makeTemporaryDirectory(prefix: "SwiftWABackupAPI-cli-export-extracted")
        defer { try? PublicTestSupport.removeItemIfExists(at: temporaryRoot) }
        let extractedDirectory = temporaryRoot.appendingPathComponent("WhatsApp", isDirectory: true)
        let outputDirectory = temporaryRoot.appendingPathComponent("chat-export", isDirectory: true)

        let extractResult = runCLI(arguments: [
            "extract-whatsapp-backup",
            "--iphone-backups-path", fixture.rootURL.path,
            "--output-dir", extractedDirectory.path
        ])
        XCTAssertEqual(extractResult.code, 0)

        let result = runCLI(arguments: [
            "export-chat",
            "--whatsapp-backup-path", extractedDirectory.path,
            "--chat-id", "44",
            "--output-dir", outputDirectory.path,
            "--pretty"
        ])

        let expectedFile = outputDirectory.appendingPathComponent("chat-44.json")

        XCTAssertEqual(result.code, 0)
        XCTAssertTrue(result.standardOutput.contains("WhatsApp backup"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: expectedFile.path))
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: outputDirectory.appendingPathComponent("fea35851-6a2c-45a3-a784-003d25576b45.pdf").path
            )
        )
    }

    func testExtractWhatsAppBackupWritesReconstructedTree() throws {
        let fixture = try PublicTestSupport.makeSampleBackup()
        defer { try? PublicTestSupport.removeItemIfExists(at: fixture.rootURL) }

        let temporaryRoot = try PublicTestSupport.makeTemporaryDirectory(prefix: "SwiftWABackupAPI-cli-extract")
        defer { try? PublicTestSupport.removeItemIfExists(at: temporaryRoot) }
        let outputDirectory = temporaryRoot.appendingPathComponent("WhatsApp", isDirectory: true)

        let result = runCLI(arguments: [
            "extract-whatsapp-backup",
            "--iphone-backups-path", fixture.rootURL.path,
            "--output-dir", outputDirectory.path
        ])

        XCTAssertEqual(result.code, 0)
        XCTAssertTrue(result.standardOutput.contains("Extracted WhatsApp backup"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputDirectory.appendingPathComponent("ChatStorage.sqlite").path))
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: outputDirectory
                    .appendingPathComponent("Media/Document/fea35851-6a2c-45a3-a784-003d25576b45.pdf")
                    .path
            )
        )
    }

    func testExtractWhatsAppBackupRendersProgressBarOnProgressOutput() throws {
        let fixture = try PublicTestSupport.makeSampleBackup()
        defer { try? PublicTestSupport.removeItemIfExists(at: fixture.rootURL) }

        let temporaryRoot = try PublicTestSupport.makeTemporaryDirectory(prefix: "SwiftWABackupAPI-cli-progress")
        defer { try? PublicTestSupport.removeItemIfExists(at: temporaryRoot) }
        let outputDirectory = temporaryRoot.appendingPathComponent("WhatsApp", isDirectory: true)

        let result = runCLI(
            arguments: [
                "extract-whatsapp-backup",
                "--iphone-backups-path", fixture.rootURL.path,
                "--output-dir", outputDirectory.path
            ],
            showsProgress: true
        )

        XCTAssertEqual(result.code, 0)
        XCTAssertTrue(result.standardOutput.contains("Extracted WhatsApp backup"))
        XCTAssertTrue(result.progressOutput.contains("Copying WhatsApp files ["))
        XCTAssertTrue(result.progressOutput.contains("100%"))
        XCTAssertTrue(result.progressOutput.contains("\r"))
    }

    func testProgressOutputDoesNotPolluteJSONStdout() throws {
        let fixture = try PublicTestSupport.makeSampleBackup()
        defer { try? PublicTestSupport.removeItemIfExists(at: fixture.rootURL) }

        let result = runCLI(
            arguments: [
                "list-iphone-backups",
                "--iphone-backups-path", fixture.rootURL.path,
                "--json"
            ],
            showsProgress: true
        )

        XCTAssertEqual(result.code, 0)
        XCTAssertFalse(result.standardOutput.contains("Inspecting iPhone backup"))
        XCTAssertTrue(result.progressOutput.contains("Inspecting iPhone backup ["))

        let data = try XCTUnwrap(result.standardOutput.data(using: .utf8))
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let iPhoneBackups = try XCTUnwrap(object?["iPhoneBackups"] as? [[String: Any]])

        XCTAssertEqual(iPhoneBackups.count, 1)
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

    func testDiagnoseConversationCompositionRequiresTargetAndSourceDirectories() {
        let missingTarget = runCLI(arguments: [
            "diagnose-conversation-composition",
            "--source-chat-dir", "/tmp/source"
        ])
        let missingSource = runCLI(arguments: [
            "diagnose-conversation-composition",
            "--target-chat-dir", "/tmp/target"
        ])

        XCTAssertEqual(missingTarget.code, 1)
        XCTAssertTrue(missingTarget.standardError.contains("Missing required argument --target-chat-dir."))
        XCTAssertEqual(missingSource.code, 1)
        XCTAssertTrue(missingSource.standardError.contains("At least one --source-chat-dir is required."))
    }

    func testDiagnoseConversationCompositionEmitsPrivacySafeJSON() throws {
        let fixture = try ConversationFixture()
        defer { fixture.remove() }
        let messages: [ConversationFixture.Message] = [
            .text(id: 1, chatID: 1, offset: 1, text: "First private shared message"),
            .text(id: 2, chatID: 1, offset: 2, text: "Second private shared message"),
            .text(id: 3, chatID: 1, offset: 3, text: "Third private shared message")
        ]
        let target = try fixture.source(
            id: "target-fixture",
            chatID: 1,
            jid: "family-private@g.us",
            name: "Private family name",
            messages: messages
        )
        let source = try fixture.source(
            id: "source-fixture",
            chatID: 2,
            jid: "family-private@g.us",
            name: "Private family name",
            messages: messages.map {
                .text(
                    id: $0.id + 10,
                    chatID: 2,
                    offset: $0.offset,
                    text: $0.text ?? ""
                )
            }
        )
        let targetDirectory = try writeChatDirectory(for: target)
        let sourceDirectory = try writeChatDirectory(for: source)

        let result = runCLI(arguments: [
            "diagnose-conversation-composition",
            "--target-chat-dir", targetDirectory.path,
            "--source-chat-dir", sourceDirectory.path,
            "--target-perspective-jid", "34600000001@s.whatsapp.net",
            "--source-perspective-jid", "34600000001@s.whatsapp.net",
            "--pretty"
        ])

        XCTAssertEqual(result.code, 0, result.standardError)
        XCTAssertFalse(result.standardOutput.contains("First private shared message"))
        XCTAssertFalse(result.standardOutput.contains("Private family name"))
        XCTAssertFalse(result.standardOutput.contains("family-private@g.us"))
        XCTAssertFalse(result.standardOutput.contains("34600000001"))
        let data = try XCTUnwrap(result.standardOutput.data(using: .utf8))
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        XCTAssertEqual(object["disposition"] as? String, "applicable")
        XCTAssertEqual(object["profile"] as? String, "conservativeCrossPerspective")
    }

    func testUnknownCommandReturnsError() throws {
        let result = runCLI(arguments: ["wat"])

        XCTAssertEqual(result.code, 1)
        XCTAssertTrue(result.standardError.contains("Unknown command 'wat'."))
    }

    private func runCLI(
        arguments: [String],
        showsProgress: Bool? = nil
    ) -> (code: Int32, standardOutput: String, standardError: String, progressOutput: String) {
        var standardOutput: [String] = []
        var standardError: [String] = []
        var progressOutput: [String] = []

        let application = CLIApplication()
        let code = application.run(
            arguments: arguments,
            standardOutput: { standardOutput.append($0) },
            standardError: { standardError.append($0) },
            progressOutput: { progressOutput.append($0) },
            showsProgress: showsProgress
        )

        return (
            code,
            standardOutput.joined(separator: "\n"),
            standardError.joined(separator: "\n"),
            progressOutput.joined()
        )
    }

    private func writeChatDirectory(for source: ConversationSource) throws -> URL {
        let directory = source.mediaDirectoryURL.deletingLastPathComponent()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(source.document).write(
            to: directory.appendingPathComponent("chat.json"),
            options: .atomic
        )
        return directory
    }
}

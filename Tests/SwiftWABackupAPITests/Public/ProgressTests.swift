import Foundation
import XCTest
@testable import SwiftWABackupAPI

final class ProgressTests: XCTestCase {
    func testInspectIPhoneBackupsReportsDiscoveryProgress() throws {
        let fixture = try PublicTestSupport.makeSampleBackup()
        defer { try? PublicTestSupport.removeItemIfExists(at: fixture.rootURL) }

        let manager = IPhoneBackupManager(iPhoneBackupsPath: fixture.rootURL.path)
        var events: [WABackupProgress] = []

        let infos = try manager.inspectIPhoneBackups { events.append($0) }

        XCTAssertEqual(infos.count, 1)
        XCTAssertTrue(events.contains { $0.phase == .discoveringIPhoneBackups })
        XCTAssertTrue(events.contains { $0.phase == .inspectingIPhoneBackup })
        XCTAssertEqual(events.last?.phase, .completed)

        let inspectionEvent = try XCTUnwrap(events.last { $0.phase == .inspectingIPhoneBackup })
        XCTAssertEqual(inspectionEvent.completedUnitCount, 1)
        XCTAssertEqual(inspectionEvent.totalUnitCount, 1)
        XCTAssertEqual(inspectionEvent.unit, .backups)
        XCTAssertEqual(inspectionEvent.fractionCompleted, 1.0)
    }

    func testExtractWhatsAppBackupReportsCopyAndMetadataProgress() throws {
        let fixture = try PublicTestSupport.makeSampleBackup()
        defer { try? PublicTestSupport.removeItemIfExists(at: fixture.rootURL) }

        let extractedRoot = try PublicTestSupport.makeTemporaryDirectory(prefix: "SwiftWABackupAPI-progress-extract")
        defer { try? PublicTestSupport.removeItemIfExists(at: extractedRoot) }

        var events: [WABackupProgress] = []
        _ = try fixture.backup.extractWhatsAppBackup(to: extractedRoot, overwriteExisting: true) {
            events.append($0)
        }

        XCTAssertTrue(events.contains { $0.phase == .loadingManifest })
        XCTAssertTrue(events.contains { $0.phase == .copyingBackupFiles })
        XCTAssertTrue(events.contains { $0.phase == .indexingFiles })
        XCTAssertTrue(events.contains { $0.phase == .indexingPathAliases })
        XCTAssertTrue(events.contains { $0.phase == .indexingMediaItems })
        XCTAssertTrue(events.contains { $0.phase == .calculatingBackupInfo })
        XCTAssertTrue(events.contains { $0.phase == .writingMetadata })
        XCTAssertEqual(events.last?.phase, .completed)

        let copyEvent = try XCTUnwrap(events.last { $0.phase == .copyingBackupFiles })
        XCTAssertEqual(copyEvent.completedUnitCount, copyEvent.totalUnitCount)
        XCTAssertEqual(copyEvent.unit, .manifestEntries)

        let metadataEvent = try XCTUnwrap(events.last { $0.phase == .writingMetadata })
        XCTAssertEqual(metadataEvent.completedUnitCount, 3)
        XCTAssertEqual(metadataEvent.totalUnitCount, 3)
        XCTAssertEqual(metadataEvent.fractionCompleted, 1.0)
    }

    func testChatListingAndExportReportProgress() throws {
        let (reader, fixture) = try PublicTestSupport.makeConnectedSampleBackup()
        defer { try? PublicTestSupport.removeItemIfExists(at: fixture.rootURL) }

        var listEvents: [WABackupProgress] = []
        let chats = try reader.getChats { listEvents.append($0) }

        XCTAssertEqual(chats.count, 2)
        XCTAssertTrue(listEvents.contains { $0.phase == .loadingChats })
        XCTAssertEqual(listEvents.last?.phase, .completed)

        let chat = try XCTUnwrap(chats.first { $0.id == 44 })
        let mediaDirectory = try PublicTestSupport.makeTemporaryDirectory(prefix: "SwiftWABackupAPI-progress-chat")
        defer { try? PublicTestSupport.removeItemIfExists(at: mediaDirectory) }

        var exportEvents: [WABackupProgress] = []
        let payload = try reader.getChat(chatId: chat.id, directoryToSaveMedia: mediaDirectory) {
            exportEvents.append($0)
        }

        XCTAssertTrue(exportEvents.contains { $0.phase == .exportingChat })
        XCTAssertTrue(exportEvents.contains { $0.phase == .loadingMessages })
        XCTAssertTrue(exportEvents.contains { $0.phase == .processingMessages })
        XCTAssertTrue(exportEvents.contains { $0.phase == .buildingContacts })
        XCTAssertTrue(exportEvents.contains { $0.phase == .exportingMedia })
        XCTAssertEqual(exportEvents.last?.phase, .completed)

        let messagesEvent = try XCTUnwrap(exportEvents.last { $0.phase == .processingMessages })
        XCTAssertEqual(messagesEvent.completedUnitCount, payload.messages.count)
        XCTAssertEqual(messagesEvent.totalUnitCount, payload.messages.count)
        XCTAssertEqual(messagesEvent.unit, .messages)
    }
}

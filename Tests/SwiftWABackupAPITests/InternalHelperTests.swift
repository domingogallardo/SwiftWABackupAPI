import XCTest
@testable import SwiftWABackupAPI
import GRDB

final class InternalHelperTests: XCTestCase {
    func testJidHelpersDetectSupportedFormats() {
        XCTAssertEqual("34600111222@s.whatsapp.net".jidUser, "34600111222")
        XCTAssertEqual("34600111222@s.whatsapp.net".jidDomain, "s.whatsapp.net")
        XCTAssertTrue("34600111222@s.whatsapp.net".isIndividualJid)
        XCTAssertFalse("34600111222@s.whatsapp.net".isGroupJid)
        XCTAssertTrue("34600111222-123456@g.us".isGroupJid)
        XCTAssertEqual("34600111222-123456@g.us".extractedPhone, "34600111222-123456")
    }

    func testQuestionMarksProducesSQLPlaceholderList() {
        XCTAssertEqual(1.questionMarks, "?")
        XCTAssertEqual(3.questionMarks, "?, ?, ?")
        XCTAssertEqual(0.questionMarks, "")
    }

    func testLatestFileReturnsHighestTimestampMatch() {
        let files: [FilenameAndHash] = [
            ("Media/Profile/123-100.jpg", "hash-old"),
            ("Media/Profile/123-250.jpg", "hash-new"),
            ("Media/Profile/123-150.jpg", "hash-mid")
        ]

        let latest = FileUtils.latestFile(for: "Media/Profile/123", fileExtension: "jpg", in: files)

        XCTAssertEqual(latest?.filename, "Media/Profile/123-250.jpg")
        XCTAssertEqual(latest?.fileHash, "hash-new")
    }

    func testCheckTableSchemaRejectsMissingColumns() throws {
        let dbQueue = try DatabaseQueue()
        try dbQueue.write { db in
            try db.execute(sql: "CREATE TABLE Demo (id INTEGER PRIMARY KEY, name TEXT)")
        }

        XCTAssertThrowsError(try dbQueue.read { db in
            try checkTableSchema(tableName: "Demo", expectedColumns: ["ID", "MISSING"], in: db)
        }) { error in
            guard case DatabaseErrorWA.unsupportedSchema = error else {
                return XCTFail("Expected DatabaseErrorWA.unsupportedSchema, got \(error)")
            }
        }
    }

    func testReactionParserParsesKnownFixtureReaction() throws {
        let receiptInfo = TestSupport.sampleReactionReceiptInfo(emoji: "😢", senderPhone: "34636104084")
        let reactions = ReactionParser.parse(receiptInfo)

        XCTAssertEqual(reactions?.count, 1)
        XCTAssertEqual(reactions?.first?.emoji, "😢")
        XCTAssertEqual(reactions?.first?.senderPhone, "34636104084")
    }
}

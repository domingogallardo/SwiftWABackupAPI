import XCTest
@testable import SwiftWABackupAPI
import GRDB

final class InternalHelperTests: XCTestCase {
    func testJidHelpersDetectSupportedFormats() {
        XCTAssertEqual("08185296376@s.whatsapp.net".jidUser, "08185296376")
        XCTAssertEqual("08185296376@s.whatsapp.net".jidDomain, "s.whatsapp.net")
        XCTAssertTrue("08185296376@s.whatsapp.net".isIndividualJid)
        XCTAssertFalse("08185296376@s.whatsapp.net".isGroupJid)
        XCTAssertTrue("08185296376-123456@g.us".isGroupJid)
        XCTAssertEqual("08185296376-123456@g.us".extractedPhone, "08185296376-123456")
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
        let receiptInfo = PublicTestSupport.sampleReactionReceiptInfo(emoji: "😢", senderPhone: "08185296386")
        let reactions = ReactionParser.parse(receiptInfo)

        XCTAssertEqual(reactions?.count, 1)
        XCTAssertEqual(reactions?.first?.emoji, "😢")
        XCTAssertEqual(reactions?.first?.author.kind, .participant)
        XCTAssertEqual(reactions?.first?.author.phone, "08185296386")
    }

    func testReactionParserResolvesLidSenderViaResolver() throws {
        let receiptInfo = PublicTestSupport.sampleReactionReceiptInfo(
            emoji: "👍",
            senderJid: "404826482604828@lid"
        )

        let reactions = ReactionParser.parse(receiptInfo) { jid in
            guard jid == "404826482604828@lid" else {
                return nil
            }

            return MessageAuthor(
                kind: .participant,
                displayName: "~ Alias Ember",
                phone: "08185296388",
                jid: "404826482604828@lid",
                source: .lidAccount
            )
        }

        XCTAssertEqual(reactions?.count, 1)
        XCTAssertEqual(reactions?.first?.emoji, "👍")
        XCTAssertEqual(reactions?.first?.author.displayName, "~ Alias Ember")
        XCTAssertEqual(reactions?.first?.author.phone, "08185296388")
    }

    func testReactionParserPreservesHeartEmojiVariationSelector() throws {
        let receiptInfo = PublicTestSupport.sampleReactionReceiptInfo(
            emoji: "❤️",
            senderJid: "4048264826043@lid"
        )

        let reactions = ReactionParser.parse(receiptInfo) { jid in
            guard jid == "4048264826043@lid" else {
                return nil
            }

            return MessageAuthor(
                kind: .participant,
                displayName: "~ Alias Flint",
                phone: "08185296373",
                jid: "4048264826043@lid",
                source: .lidAccount
            )
        }

        XCTAssertEqual(reactions?.count, 1)
        XCTAssertEqual(reactions?.first?.emoji, "❤️")
        XCTAssertEqual(reactions?.first?.author.displayName, "~ Alias Flint")
        XCTAssertEqual(reactions?.first?.author.phone, "08185296373")
    }

    func testMediaItemReplyParserHandlesModernPhoneBasedMetadata() throws {
        let mediaItem = try makeMediaItem(
            metadata: Data(
                [0x2A, 0x06]
                    + Array("orig-1".utf8)
                    + [0x32, 0x1A]
                    + Array("08185296386@s.whatsapp.net".utf8)
            )
        )

        XCTAssertEqual(mediaItem.extractReplyStanzaId(), "orig-1")
    }

    func testMediaItemReplyParserHandlesModernLidBasedMetadata() throws {
        let mediaItem = try makeMediaItem(
            metadata: Data(
                [0x2A, 0x14]
                    + Array("3A05149DCDBC09B2552E".utf8)
                    + [0x32, 0x13]
                    + Array("404826482604828@lid".utf8)
            )
        )

        XCTAssertEqual(mediaItem.extractReplyStanzaId(), "3A05149DCDBC09B2552E")
    }

    private func makeMediaItem(metadata: Data) throws -> MediaItem {
        let dbQueue = try DatabaseQueue()
        try dbQueue.write { db in
            try db.execute(sql: """
                CREATE TABLE ZWAMEDIAITEM (
                    Z_PK INTEGER PRIMARY KEY,
                    ZMETADATA BLOB,
                    ZTITLE TEXT,
                    ZMEDIALOCALPATH TEXT,
                    ZMOVIEDURATION INTEGER,
                    ZLATITUDE DOUBLE,
                    ZLONGITUDE DOUBLE
                )
                """)

            try db.execute(
                sql: """
                    INSERT INTO ZWAMEDIAITEM
                    (Z_PK, ZMETADATA, ZTITLE, ZMEDIALOCALPATH, ZMOVIEDURATION, ZLATITUDE, ZLONGITUDE)
                    VALUES (1, ?, NULL, NULL, NULL, NULL, NULL)
                    """,
                arguments: [metadata]
            )
        }

        return try dbQueue.read { db in
            try XCTUnwrap(MediaItem.fetchMediaItem(byId: 1, from: db))
        }
    }
}

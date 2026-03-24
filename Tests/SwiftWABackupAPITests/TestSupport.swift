import Foundation
import XCTest
@testable import SwiftWABackupAPI
import GRDB

enum TestSupport {
    static let bundledBackupIdentifier = "00008101-000478893600801E"

    static let fixtureRoot: URL = {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Data")
            .standardizedFileURL
    }()

    static let bundledBackupDirectory: URL = fixtureRoot.appendingPathComponent(bundledBackupIdentifier)

    static func makeWABackup() -> WABackup {
        WABackup(backupPath: fixtureRoot.path)
    }

    static func firstBundledBackup() throws -> IPhoneBackup {
        let waBackup = makeWABackup()
        let backups = try waBackup.getBackups()
        return try XCTUnwrap(backups.validBackups.first, "Expected the bundled fixture backup to exist")
    }

    static func makeConnectedBackup() throws -> (waBackup: WABackup, backup: IPhoneBackup) {
        let waBackup = makeWABackup()
        let backup = try firstBundledBackup()
        try waBackup.connectChatStorageDb(from: backup)
        return (waBackup, backup)
    }

    static func makeSampleBackup() throws -> TemporaryBackupFixture {
        let documentPath = "Media/Document/fea35851-6a2c-45a3-a784-003d25576b45.pdf"

        return try makeTemporaryBackup(
            name: "sample-backup",
            additionalManifestEntries: [
                BackupStoredFile(
                    relativePath: documentPath,
                    fileHash: "cd1234567890sampledocument",
                    contents: Data("Sample PDF contents".utf8)
                )
            ]
        ) { db in
            try db.execute(sql: """
                CREATE TABLE ZWACHATSESSION (
                    Z_PK INTEGER PRIMARY KEY,
                    ZCONTACTJID TEXT,
                    ZPARTNERNAME TEXT,
                    ZLASTMESSAGEDATE DOUBLE,
                    ZMESSAGECOUNTER INTEGER,
                    ZSESSIONTYPE INTEGER,
                    ZARCHIVED INTEGER
                )
                """)
            try db.execute(sql: """
                CREATE TABLE ZWAMESSAGE (
                    Z_PK INTEGER PRIMARY KEY,
                    ZTOJID TEXT,
                    ZMESSAGETYPE INTEGER,
                    ZGROUPMEMBER INTEGER,
                    ZCHATSESSION INTEGER,
                    ZTEXT TEXT,
                    ZMESSAGEDATE DOUBLE,
                    ZFROMJID TEXT,
                    ZMEDIAITEM INTEGER,
                    ZISFROMME INTEGER,
                    ZGROUPEVENTTYPE INTEGER,
                    ZSTANZAID TEXT
                )
                """)
            try db.execute(sql: """
                CREATE TABLE ZWAGROUPMEMBER (
                    Z_PK INTEGER PRIMARY KEY,
                    ZMEMBERJID TEXT,
                    ZCONTACTNAME TEXT
                )
                """)
            try db.execute(sql: """
                CREATE TABLE ZWAPROFILEPUSHNAME (
                    ZPUSHNAME TEXT,
                    ZJID TEXT
                )
                """)
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
            try db.execute(sql: """
                CREATE TABLE ZWAMESSAGEINFO (
                    Z_PK INTEGER PRIMARY KEY,
                    ZRECEIPTINFO BLOB,
                    ZMESSAGE INTEGER
                )
                """)

            let chat44Latest = referenceDateTimestamp(year: 2024, month: 4, day: 3, hour: 11, minute: 24, second: 16)
            let chat593Latest = referenceDateTimestamp(year: 2024, month: 4, day: 2, hour: 10, minute: 0, second: 0)

            try db.execute(
                sql: """
                    INSERT INTO ZWACHATSESSION
                    (Z_PK, ZCONTACTJID, ZPARTNERNAME, ZLASTMESSAGEDATE, ZMESSAGECOUNTER, ZSESSIONTYPE, ZARCHIVED)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [44, "34636104084@s.whatsapp.net", "Aitor Medrano", chat44Latest, 3, 0, 0]
            )
            try db.execute(
                sql: """
                    INSERT INTO ZWACHATSESSION
                    (Z_PK, ZCONTACTJID, ZPARTNERNAME, ZLASTMESSAGEDATE, ZMESSAGECOUNTER, ZSESSIONTYPE, ZARCHIVED)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [593, "34600000001@s.whatsapp.net", "Business Contact", chat593Latest, 2, 0, 0]
            )

            try db.execute(
                sql: """
                    INSERT INTO ZWAMEDIAITEM
                    (Z_PK, ZMETADATA, ZTITLE, ZMEDIALOCALPATH, ZMOVIEDURATION, ZLATITUDE, ZLONGITUDE)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [9001, sampleReplyMetadata(replyingTo: "orig-1"), nil, nil, nil, nil, nil]
            )
            try db.execute(
                sql: """
                    INSERT INTO ZWAMEDIAITEM
                    (Z_PK, ZMETADATA, ZTITLE, ZMEDIALOCALPATH, ZMOVIEDURATION, ZLATITUDE, ZLONGITUDE)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [9002, nil, nil, documentPath, nil, nil, nil]
            )

            try db.execute(
                sql: """
                    INSERT INTO ZWAMESSAGE
                    (Z_PK, ZTOJID, ZMESSAGETYPE, ZGROUPMEMBER, ZCHATSESSION, ZTEXT, ZMESSAGEDATE, ZFROMJID, ZMEDIAITEM, ZISFROMME, ZGROUPEVENTTYPE, ZSTANZAID)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    125479,
                    "34636104084@s.whatsapp.net",
                    0,
                    nil,
                    44,
                    "Original message",
                    referenceDateTimestamp(year: 2024, month: 4, day: 3, hour: 11, minute: 0, second: 0),
                    nil,
                    nil,
                    1,
                    nil,
                    "orig-1"
                ]
            )
            try db.execute(
                sql: """
                    INSERT INTO ZWAMESSAGE
                    (Z_PK, ZTOJID, ZMESSAGETYPE, ZGROUPMEMBER, ZCHATSESSION, ZTEXT, ZMESSAGEDATE, ZFROMJID, ZMEDIAITEM, ZISFROMME, ZGROUPEVENTTYPE, ZSTANZAID)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    125482,
                    "34693206402@s.whatsapp.net",
                    0,
                    nil,
                    44,
                    "Claro, cada vez que vaya a la UA te aviso.",
                    chat44Latest,
                    "34636104084@s.whatsapp.net",
                    9001,
                    0,
                    nil,
                    "reply-1"
                ]
            )
            try db.execute(
                sql: """
                    INSERT INTO ZWAMESSAGE
                    (Z_PK, ZTOJID, ZMESSAGETYPE, ZGROUPMEMBER, ZCHATSESSION, ZTEXT, ZMESSAGEDATE, ZFROMJID, ZMEDIAITEM, ZISFROMME, ZGROUPEVENTTYPE, ZSTANZAID)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    126279,
                    "34693206402@s.whatsapp.net",
                    8,
                    nil,
                    44,
                    "DIARIO INFORMACION PIA LARA.pdf",
                    referenceDateTimestamp(year: 2024, month: 4, day: 3, hour: 10, minute: 30, second: 0),
                    "34636104084@s.whatsapp.net",
                    9002,
                    0,
                    nil,
                    "doc-1"
                ]
            )
            try db.execute(
                sql: """
                    INSERT INTO ZWAMESSAGE
                    (Z_PK, ZTOJID, ZMESSAGETYPE, ZGROUPMEMBER, ZCHATSESSION, ZTEXT, ZMESSAGEDATE, ZFROMJID, ZMEDIAITEM, ZISFROMME, ZGROUPEVENTTYPE, ZSTANZAID)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    200001,
                    "34693206402@s.whatsapp.net",
                    10,
                    nil,
                    593,
                    nil,
                    chat593Latest,
                    "34600000001@s.whatsapp.net",
                    nil,
                    0,
                    38,
                    "status-1"
                ]
            )
            try db.execute(
                sql: """
                    INSERT INTO ZWAMESSAGE
                    (Z_PK, ZTOJID, ZMESSAGETYPE, ZGROUPMEMBER, ZCHATSESSION, ZTEXT, ZMESSAGEDATE, ZFROMJID, ZMEDIAITEM, ZISFROMME, ZGROUPEVENTTYPE, ZSTANZAID)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    200002,
                    "34693206402@s.whatsapp.net",
                    0,
                    nil,
                    593,
                    "Hello from business",
                    referenceDateTimestamp(year: 2024, month: 4, day: 2, hour: 9, minute: 0, second: 0),
                    "34600000001@s.whatsapp.net",
                    nil,
                    0,
                    nil,
                    "business-text-1"
                ]
            )

            try db.execute(
                sql: """
                    INSERT INTO ZWAMESSAGEINFO
                    (Z_PK, ZRECEIPTINFO, ZMESSAGE)
                    VALUES (?, ?, ?)
                    """,
                arguments: [1, sampleReactionReceiptInfo(emoji: "😢", senderPhone: "34636104084"), 125482]
            )
        }
    }

    static func makeConnectedSampleBackup() throws -> (waBackup: WABackup, fixture: TemporaryBackupFixture) {
        let fixture = try makeSampleBackup()
        let waBackup = WABackup(backupPath: fixture.rootURL.path)
        try waBackup.connectChatStorageDb(from: fixture.backup)
        return (waBackup, fixture)
    }

    static func requireFullFixtureRun() throws {
        if ProcessInfo.processInfo.environment["SWIFT_WA_RUN_FULL_FIXTURE_TESTS"] != "1" {
            throw XCTSkip("Skipping full regression fixture suite. Set SWIFT_WA_RUN_FULL_FIXTURE_TESTS=1 to enable it.")
        }

        if !FileManager.default.fileExists(atPath: bundledBackupDirectory.path) {
            throw XCTSkip("Skipping full regression fixture suite because the large local backup fixture is not available.")
        }
    }

    static func makeCanonicalJSONEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    static func canonicalJSONString<T: Encodable>(_ value: T) throws -> String {
        let data = try makeCanonicalJSONEncoder().encode(value)
        return try XCTUnwrap(String(data: data, encoding: .utf8))
    }

    static func loadFixture(named relativePath: String) throws -> String {
        let url = fixtureRoot.appendingPathComponent(relativePath)
        let contents = try String(contentsOf: url, encoding: .utf8)
        if contents.hasSuffix("\n") {
            return String(contents.dropLast())
        }
        return contents
    }

    static func makeTemporaryDirectory(prefix: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "\(prefix)-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func removeItemIfExists(at url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    static func makeTemporaryBackup(
        name: String = UUID().uuidString,
        additionalManifestEntries: [BackupStoredFile] = [],
        chatStorageSetup: (Database) throws -> Void
    ) throws -> TemporaryBackupFixture {
        let rootURL = try makeTemporaryDirectory(prefix: "SwiftWABackupAPI-tests")
        let backupURL = rootURL.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: backupURL, withIntermediateDirectories: true)

        let creationDate = Date(timeIntervalSince1970: 1_711_267_200)
        try writePlist([:], to: backupURL.appendingPathComponent("Info.plist"))
        try writePlist(["Date": creationDate], to: backupURL.appendingPathComponent("Status.plist"))

        let fileHash = "ab1234567890chatstorage"
        try createManifestDatabase(
            at: backupURL.appendingPathComponent("Manifest.db"),
            chatStorageHash: fileHash
        )

        for storedFile in additionalManifestEntries {
            try addManifestEntry(storedFile, toBackupAt: backupURL)
        }

        let hashDirectory = backupURL.appendingPathComponent(String(fileHash.prefix(2)), isDirectory: true)
        try FileManager.default.createDirectory(at: hashDirectory, withIntermediateDirectories: true)
        let chatStorageURL = hashDirectory.appendingPathComponent(fileHash)
        let chatStorageQueue = try DatabaseQueue(path: chatStorageURL.path)
        try chatStorageQueue.write(chatStorageSetup)

        let backup = IPhoneBackup(url: backupURL, creationDate: creationDate)
        return TemporaryBackupFixture(rootURL: rootURL, backupURL: backupURL, backup: backup)
    }

    private static func writePlist(_ object: Any, to url: URL) throws {
        let data = try PropertyListSerialization.data(fromPropertyList: object, format: .xml, options: 0)
        try data.write(to: url)
    }

    private static func createManifestDatabase(at url: URL, chatStorageHash: String) throws {
        let manifestQueue = try DatabaseQueue(path: url.path)
        try manifestQueue.write { db in
            try db.execute(sql: """
                CREATE TABLE Files (
                    fileID TEXT,
                    relativePath TEXT,
                    domain TEXT
                )
                """)

            try db.execute(
                sql: """
                    INSERT INTO Files (fileID, relativePath, domain)
                    VALUES (?, ?, ?)
                    """,
                arguments: [
                    chatStorageHash,
                    "ChatStorage.sqlite",
                    "AppDomainGroup-group.net.whatsapp.WhatsApp.shared"
                ]
            )
        }
    }

    private static func addManifestEntry(_ storedFile: BackupStoredFile, toBackupAt backupURL: URL) throws {
        let manifestQueue = try DatabaseQueue(path: backupURL.appendingPathComponent("Manifest.db").path)
        try manifestQueue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO Files (fileID, relativePath, domain)
                    VALUES (?, ?, ?)
                    """,
                arguments: [
                    storedFile.fileHash,
                    storedFile.relativePath,
                    "AppDomainGroup-group.net.whatsapp.WhatsApp.shared"
                ]
            )
        }

        let hashDirectory = backupURL.appendingPathComponent(String(storedFile.fileHash.prefix(2)), isDirectory: true)
        try FileManager.default.createDirectory(at: hashDirectory, withIntermediateDirectories: true)
        try storedFile.contents.write(to: hashDirectory.appendingPathComponent(storedFile.fileHash))
    }

    private static func referenceDateTimestamp(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int,
        second: Int
    ) -> TimeInterval {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second

        let date = components.date ?? Date(timeIntervalSinceReferenceDate: 0)
        return date.timeIntervalSinceReferenceDate
    }

    private static func sampleReplyMetadata(replyingTo stanzaID: String) -> Data {
        Data([0x00, 0x00, 0x20] + Array(stanzaID.utf8) + [0x32, 0x1A])
    }

    static func sampleReactionReceiptInfo(emoji: String, senderPhone: String) -> Data {
        let sender = Array("\(senderPhone)@s.whatsapp.net".utf8)
        let emojiBytes = Array(emoji.utf8)
        return Data(sender + [0x00, UInt8(emojiBytes.count)] + emojiBytes)
    }
}

struct TemporaryBackupFixture {
    let rootURL: URL
    let backupURL: URL
    let backup: IPhoneBackup
}

struct BackupStoredFile {
    let relativePath: String
    let fileHash: String
    let contents: Data
}

final class MediaWriteDelegateSpy: WABackupDelegate {
    private(set) var fileNames: [String] = []

    func didWriteMediaFile(fileName: String) {
        fileNames.append(fileName)
    }
}

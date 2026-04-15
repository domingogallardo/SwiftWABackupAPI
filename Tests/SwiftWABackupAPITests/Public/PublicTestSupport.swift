import Foundation
@testable import SwiftWABackupAPI
import GRDB

enum PublicTestSupport {
    static func makeSampleBackup() throws -> PublicTemporaryBackupFixture {
        let documentPath = "Media/Document/fea35851-6a2c-45a3-a784-003d25576b45.pdf"

        return try makeTemporaryBackup(
            name: "sample-backup",
            additionalManifestEntries: [
                PublicBackupStoredFile(
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
                    ZSTANZAID TEXT,
                    ZPARENTMESSAGE INTEGER
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
            let chat593Latest = referenceDateTimestamp(year: 2024, month: 4, day: 2, hour: 9, minute: 0, second: 0)

            try db.execute(
                sql: """
                    INSERT INTO ZWACHATSESSION
                    (Z_PK, ZCONTACTJID, ZPARTNERNAME, ZLASTMESSAGEDATE, ZMESSAGECOUNTER, ZSESSIONTYPE, ZARCHIVED)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [44, "08185296386@s.whatsapp.net", "Alias Atlas", chat44Latest, 3, 0, 0]
            )
            try db.execute(
                sql: """
                    INSERT INTO ZWACHATSESSION
                    (Z_PK, ZCONTACTJID, ZPARTNERNAME, ZLASTMESSAGEDATE, ZMESSAGECOUNTER, ZSESSIONTYPE, ZARCHIVED)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [593, "08185296375@s.whatsapp.net", "Business Contact", chat593Latest, 1, 0, 0]
            )

            try db.execute(
                sql: """
                    INSERT INTO ZWAMEDIAITEM
                    (Z_PK, ZMETADATA, ZTITLE, ZMEDIALOCALPATH, ZMOVIEDURATION, ZLATITUDE, ZLONGITUDE)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    9001,
                    sampleReplyMetadata(
                        replyingTo: "orig-1",
                        quotedJid: "08185296386@s.whatsapp.net"
                    ),
                    nil,
                    nil,
                    nil,
                    nil,
                    nil
                ]
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
                    (Z_PK, ZTOJID, ZMESSAGETYPE, ZGROUPMEMBER, ZCHATSESSION, ZTEXT, ZMESSAGEDATE, ZFROMJID, ZMEDIAITEM, ZISFROMME, ZGROUPEVENTTYPE, ZSTANZAID, ZPARENTMESSAGE)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    125470,
                    "08185296380@s.whatsapp.net",
                    6,
                    nil,
                    44,
                    nil,
                    referenceDateTimestamp(year: 2024, month: 4, day: 3, hour: 10, minute: 0, second: 0),
                    nil,
                    nil,
                    1,
                    nil,
                    "owner-marker-1",
                    nil
                ]
            )
            try db.execute(
                sql: """
                    INSERT INTO ZWAMESSAGE
                    (Z_PK, ZTOJID, ZMESSAGETYPE, ZGROUPMEMBER, ZCHATSESSION, ZTEXT, ZMESSAGEDATE, ZFROMJID, ZMEDIAITEM, ZISFROMME, ZGROUPEVENTTYPE, ZSTANZAID, ZPARENTMESSAGE)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    125479,
                    "08185296386@s.whatsapp.net",
                    0,
                    nil,
                    44,
                    "Original message",
                    referenceDateTimestamp(year: 2024, month: 4, day: 3, hour: 11, minute: 0, second: 0),
                    nil,
                    nil,
                    1,
                    nil,
                    "orig-1",
                    nil
                ]
            )
            try db.execute(
                sql: """
                    INSERT INTO ZWAMESSAGE
                    (Z_PK, ZTOJID, ZMESSAGETYPE, ZGROUPMEMBER, ZCHATSESSION, ZTEXT, ZMESSAGEDATE, ZFROMJID, ZMEDIAITEM, ZISFROMME, ZGROUPEVENTTYPE, ZSTANZAID, ZPARENTMESSAGE)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    125482,
                    "08185296380@s.whatsapp.net",
                    0,
                    nil,
                    44,
                    "Vale, cuando pase por la zona te escribo.",
                    chat44Latest,
                    "08185296386@s.whatsapp.net",
                    9001,
                    0,
                    nil,
                    "reply-1",
                    nil
                ]
            )
            try db.execute(
                sql: """
                    INSERT INTO ZWAMESSAGE
                    (Z_PK, ZTOJID, ZMESSAGETYPE, ZGROUPMEMBER, ZCHATSESSION, ZTEXT, ZMESSAGEDATE, ZFROMJID, ZMEDIAITEM, ZISFROMME, ZGROUPEVENTTYPE, ZSTANZAID, ZPARENTMESSAGE)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    126279,
                    "08185296380@s.whatsapp.net",
                    8,
                    nil,
                    44,
                    "ARCHIVO RESUMEN CASO DELTA.pdf",
                    referenceDateTimestamp(year: 2024, month: 4, day: 3, hour: 10, minute: 30, second: 0),
                    "08185296386@s.whatsapp.net",
                    9002,
                    0,
                    nil,
                    "doc-1",
                    nil
                ]
            )
            try db.execute(
                sql: """
                    INSERT INTO ZWAMESSAGE
                    (Z_PK, ZTOJID, ZMESSAGETYPE, ZGROUPMEMBER, ZCHATSESSION, ZTEXT, ZMESSAGEDATE, ZFROMJID, ZMEDIAITEM, ZISFROMME, ZGROUPEVENTTYPE, ZSTANZAID, ZPARENTMESSAGE)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    200002,
                    "08185296380@s.whatsapp.net",
                    0,
                    nil,
                    593,
                    "Hello from business",
                    referenceDateTimestamp(year: 2024, month: 4, day: 2, hour: 9, minute: 0, second: 0),
                    "08185296375@s.whatsapp.net",
                    nil,
                    0,
                    nil,
                    "business-text-1",
                    nil
                ]
            )

            try db.execute(
                sql: """
                    INSERT INTO ZWAMESSAGEINFO
                    (Z_PK, ZRECEIPTINFO, ZMESSAGE)
                    VALUES (?, ?, ?)
                    """,
                arguments: [1, sampleReactionReceiptInfo(emoji: "😢", senderPhone: "08185296386"), 125482]
            )
        }
    }

    static func makeConnectedSampleBackup() throws -> (waBackup: WABackup, fixture: PublicTemporaryBackupFixture) {
        let fixture = try makeSampleBackup()
        let waBackup = WABackup(backupPath: fixture.rootURL.path)
        try waBackup.connectChatStorageDb(from: fixture.backup)
        return (waBackup, fixture)
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

    static func canonicalJSONString<T: Encodable>(_ value: T) throws -> String {
        let data = try makeCanonicalJSONEncoder().encode(value)

        guard let string = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }

        return string
    }

    static func makeTemporaryBackup(
        name: String = UUID().uuidString,
        isEncrypted: Bool? = false,
        additionalManifestEntries: [PublicBackupStoredFile] = [],
        chatStorageSetup: (Database) throws -> Void
    ) throws -> PublicTemporaryBackupFixture {
        let rootURL = try makeTemporaryDirectory(prefix: "SwiftWABackupAPI-tests")
        let backupURL = rootURL.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: backupURL, withIntermediateDirectories: true)

        let creationDate = Date(timeIntervalSince1970: 1_711_267_200)
        try writePlist([:], to: backupURL.appendingPathComponent("Info.plist"))
        try writePlist(["Date": creationDate], to: backupURL.appendingPathComponent("Status.plist"))
        if let isEncrypted {
            try writePlist(["IsEncrypted": isEncrypted], to: backupURL.appendingPathComponent("Manifest.plist"))
        }

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

        let backup = IPhoneBackup(url: backupURL, creationDate: creationDate, isEncrypted: isEncrypted)
        return PublicTemporaryBackupFixture(rootURL: rootURL, backupURL: backupURL, backup: backup)
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

    private static func addManifestEntry(_ storedFile: PublicBackupStoredFile, toBackupAt backupURL: URL) throws {
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

    static func addContactsDatabase(
        to fixture: PublicTemporaryBackupFixture,
        fileHash: String = "b81234567890contactsv2",
        setup: (Database) throws -> Void
    ) throws {
        let manifestQueue = try DatabaseQueue(path: fixture.backupURL.appendingPathComponent("Manifest.db").path)
        try manifestQueue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO Files (fileID, relativePath, domain)
                    VALUES (?, ?, ?)
                    """,
                arguments: [
                    fileHash,
                    "ContactsV2.sqlite",
                    "AppDomainGroup-group.net.whatsapp.WhatsApp.shared"
                ]
            )
        }

        let hashDirectory = fixture.backupURL.appendingPathComponent(String(fileHash.prefix(2)), isDirectory: true)
        try FileManager.default.createDirectory(at: hashDirectory, withIntermediateDirectories: true)
        let contactsURL = hashDirectory.appendingPathComponent(fileHash)
        let contactsQueue = try DatabaseQueue(path: contactsURL.path)

        try contactsQueue.write { db in
            try db.execute(sql: """
                CREATE TABLE ZWAADDRESSBOOKCONTACT (
                    Z_PK INTEGER PRIMARY KEY,
                    ZFULLNAME TEXT,
                    ZGIVENNAME TEXT,
                    ZBUSINESSNAME TEXT,
                    ZLID TEXT,
                    ZPHONENUMBER TEXT,
                    ZWHATSAPPID TEXT
                )
                """)
            try setup(db)
        }
    }

    static func addLidDatabase(
        to fixture: PublicTemporaryBackupFixture,
        fileHash: String = "e71234567890lidsqlite",
        setup: (Database) throws -> Void
    ) throws {
        let manifestQueue = try DatabaseQueue(path: fixture.backupURL.appendingPathComponent("Manifest.db").path)
        try manifestQueue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO Files (fileID, relativePath, domain)
                    VALUES (?, ?, ?)
                    """,
                arguments: [
                    fileHash,
                    "LID.sqlite",
                    "AppDomainGroup-group.net.whatsapp.WhatsApp.shared"
                ]
            )
        }

        let hashDirectory = fixture.backupURL.appendingPathComponent(String(fileHash.prefix(2)), isDirectory: true)
        try FileManager.default.createDirectory(at: hashDirectory, withIntermediateDirectories: true)
        let lidURL = hashDirectory.appendingPathComponent(fileHash)
        let lidQueue = try DatabaseQueue(path: lidURL.path)

        try lidQueue.write { db in
            try db.execute(sql: """
                CREATE TABLE ZWAZACCOUNT (
                    Z_PK INTEGER PRIMARY KEY,
                    ZIDENTIFIER TEXT,
                    ZPHONENUMBER TEXT,
                    ZCREATEDAT DOUBLE
                )
                """)
            try setup(db)
        }
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

    private static func makeCanonicalJSONEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static func sampleReplyMetadata(replyingTo stanzaID: String, quotedJid: String) -> Data {
        Data(
            [0x2A, UInt8(stanzaID.utf8.count)]
                + Array(stanzaID.utf8)
                + [0x32, UInt8(quotedJid.utf8.count)]
                + Array(quotedJid.utf8)
        )
    }

    static func sampleReactionReceiptInfo(emoji: String, senderPhone: String) -> Data {
        sampleReactionReceiptInfo(emoji: emoji, senderJid: "\(senderPhone)@s.whatsapp.net")
    }

    static func sampleReactionReceiptInfo(emoji: String, senderJid: String) -> Data {
        let stanzaID = Array("3A038549B0680F155E6F".utf8)
        let sender = Array(senderJid.utf8)
        let emojiBytes = Array(emoji.utf8)
        let reactionEntry = [0x0A, UInt8(stanzaID.count)] + stanzaID
            + [0x12, UInt8(sender.count)] + sender
            + [0x1A, UInt8(emojiBytes.count)] + emojiBytes
            + [0x20, 0x01, 0x28, 0x02, 0x38, 0x00]

        return Data([0x3A, UInt8(reactionEntry.count + 2), 0x0A, UInt8(reactionEntry.count)] + reactionEntry)
    }
}

struct PublicTemporaryBackupFixture {
    let rootURL: URL
    let backupURL: URL
    let backup: IPhoneBackup
}

struct PublicBackupStoredFile {
    let relativePath: String
    let fileHash: String
    let contents: Data
}

final class PublicMediaWriteDelegateSpy: WABackupDelegate {
    private(set) var fileNames: [String] = []

    func didWriteMediaFile(fileName: String) {
        fileNames.append(fileName)
    }
}

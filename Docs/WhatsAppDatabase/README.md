# WhatsApp Database Reference

This project works against the `ChatStorage.sqlite` database extracted from an iOS backup of WhatsApp. The behaviour described here is derived from the current implementation under `Sources/SwiftWABackupAPI` and is continuously verified by the XCTest suite in `Tests/SwiftWABackupAPITests`.

## Source of Truth

The observations below come from three places:

- Source files under `Sources/SwiftWABackupAPI`, particularly `SwiftWABackupAPI.swift`, `Message.swift`, `MediaItem.swift`, and supporting helpers.
- The bundled fixture database `Tests/Data/ChatStorage.sqlite` plus ancillary test assets under `Tests/Data/`.
- The XCTest targets in `Tests/SwiftWABackupAPITests`, which exercise the API end-to-end and assert expectations against the fixture.

When upgrading WhatsApp versions or altering the fixture, re-run `swift test` and update this document with any schema or mapping changes you observe.

## Core Tables and Columns

| Table | Purpose | Key Columns Used |
| --- | --- | --- |
| `ZWAMESSAGE` | Stores every chat message and system event. | `Z_PK`, `ZCHATSESSION`, `ZMESSAGETYPE`, `ZGROUPEVENTTYPE`, `ZTEXT`, `ZMEDIAITEM`, `ZISFROMME`, `ZGROUPMEMBER`, `ZMESSAGEDATE`, `ZFROMJID`, `ZTOJID` |
| `ZWACHATSESSION` | Metadata for each chat thread. | `Z_PK`, `ZCONTACTJID`, `ZPARTNERNAME`, `ZLASTMESSAGEDATE`, `ZMESSAGECOUNTER`, `ZSESSIONTYPE`, `ZARCHIVED` |
| `ZWAMEDIAITEM` | Metadata for media attached to messages. | `Z_PK`, `ZMEDIALOCALPATH`, `ZTITLE`, `ZMOVIEDURATION`, `ZLATITUDE`, `ZLONGITUDE`, `ZMETADATA` |
| `ZWAGROUPMEMBER` | Group participant roster used to resolve sender info. | `Z_PK`, `ZMEMBERJID`, `ZCONTACTNAME` |
| `ZWAMESSAGEINFO` | Reaction payloads (`ZRECEIPTINFO`). | `ZMESSAGE`, `ZRECEIPTINFO` |
| `ZWAVCARDMENTION` | vCard contact references for contact messages. | `ZMEDIAITEM`, `ZWHATSAPPID`, `ZSENDERJID` |

All schema checks live in `DatabaseHelpers.swift` and `DatabaseProtocols.swift`; each model declares the minimal column set that the tests expect to find.

## Message Type Mapping

`ZMESSAGETYPE` is converted into the following enum in `SwiftWABackupAPI.swift`:

| Code | Description | Notes |
| --- | --- | --- |
| 0 | Text | Plain messages; text preserved in `ZTEXT`. |
| 1 | Image | Copies media to disk when requested and exposes filename. |
| 2 | Video | Adds filename and duration (`ZMOVIEDURATION`). |
| 3 | Audio | Adds filename and duration. |
| 4 | Contact | Extracts vCard info from `ZWAVCARDMENTION`. |
| 5 | Location | Emits latitude/longitude (`ZLATITUDE`, `ZLONGITUDE`). |
| 7 | Link | Keeps URL text and optional caption. |
| 8 | Document | Exposes original file name and caption. |
| 10 | Status | System/business events; see subcodes below. |
| 11 | GIF | Treated like video, stored as MP4 in the backup. |
| 15 | Sticker | Returns `.webp` filename. |

`SwiftWABackupAPITests.testChatMessages` verifies that the counts for each supported type are stable against the fixture (e.g. 5532 images, 489 videos, 310 statuses).

### Status (`ZMESSAGETYPE = 10`) Subcodes (Fixture Snapshot)

| Subcode | Count | Observed payload | Current handling |
| --- | --- | --- | --- |
| 2 | 217 | Empty `ZTEXT`; `ZFROMJID` set to contact | Rendered as `Status sync from …` using sender info (new behaviour). |
| 1 | 24 | Empty text, same shape as `2` | Currently treated as raw status; candidate for sync label. |
| 38 | 15 | Business chat event; no text/media | Replaced with `"This is a business chat"`. |
| 21 / 22 | 8 / 3 | `ZTEXT` lists JIDs separated by commas | Left as-is; indicates broadcast/contact list updates. |
| 26 | 7 | `ZTEXT` contains a business/contact display name | Left as-is. |
| 40 / 41 | 4 / 7 | `ZTEXT` is a hash-like identifier | Left as-is; likely media sync tokens. |
| 56 / 58 | 8 / 5 | Empty text, group JID in `ZFROMJID` for 58 | Left as-is; appear to be group status sync events. |

Subcodes `5, 6, 13, 14, 25, 29, 30, 31, 34` also exist but with very low counts. Mapping these to descriptive messages would be a useful future enhancement.

## Sender Name Resolution

When building `MessageInfo`, the API determines the sender identity with a cascading strategy:

1. **Outgoing messages (`ZISFROMME = 1`)** – Treated as authored by the owner, so `senderName`/`senderPhone` remain `nil`; callers can display "Me".
2. **Group chats** – `ZWAMESSAGE.ZGROUPMEMBER` links to `ZWAGROUPMEMBER.Z_PK`:
   - `obtainSenderInfo` tries `ZWACHATSESSION.ZPARTNERNAME` first, then `ZWAPROFILEPUSHNAME`, and finally `ZWAGROUPMEMBER.ZCONTACTNAME`.
   - `String.extractedPhone` derives the phone number from the member JID.
3. **Individual chats** – `ZCHATSESSION` points to `ZWACHATSESSION`; the partner name/JID there provide the sender name and phone when the message is not from the owner.

This behaviour lives in `SwiftWABackupAPI.swift` (`fetchSenderInfo`, `fetchGroupMemberInfo`, `fetchIndividualChatSenderInfo`, `obtainSenderInfo`) and is verified by `SwiftWABackupAPITests.testMessageContentExtraction`.

## Reply Resolution

Replies are encoded through media metadata rather than a direct foreign key:

1. `ZWAMESSAGE.ZMEDIAITEM` references a `ZWAMEDIAITEM` row whose `ZMETADATA` holds a protobuf-style blob. Messages without a media item cannot resolve replies and keep `replyTo = nil`.
2. `MediaItem.extractReplyStanzaId()` scans that blob for reply markers (`0x32 0x1A` or `0x9A 0x01`) and extracts the original stanza ID.
3. `WABackup.fetchReplyMessageId` uses `Message.fetchMessageId(byStanzaId:)` to locate the original `ZWAMESSAGE.Z_PK`.
4. If found, `MessageInfo.replyTo` contains the target message ID; otherwise it remains `nil`.

`SwiftWABackupAPITests.testMessageContentExtraction` asserts this behaviour (e.g. message 125482 replying to 125479 in the fixture). Parsing failures are tolerated, resulting in a `nil` reply.

## Reaction Storage

- Reactions live in `ZWAMESSAGEINFO.ZRECEIPTINFO` as binary blobs. Entries only exist for messages that received reactions.
- `ReactionParser` iterates each blob byte-by-byte: the first byte gives the emoji length, the slice contains the UTF‑8 emoji, and preceding bytes encode the reacting JID (ending in `@s.whatsapp.net`).
- Parsed reactions become `[Reaction]` (emoji + phone), attached to `MessageInfo.reactions`.
- `SwiftWABackupAPITests.testMessageContentExtraction` exercises messages with and without reactions to confirm the parser output stays stable.

## Media Retrieval & Manifest Lookup

- Media files referenced in `ZWAMESSAGE` are stored in the iTunes backup under hashed paths. `IPhoneBackup.fetchWAFileHash` queries `Manifest.db` (`domain = 'AppDomainGroup-group.net.whatsapp.WhatsApp.shared'`) to translate a relative path such as `Media/345.../file.jpg` into the hash used on disk.
- `MediaCopier` then copies the hashed file from `<backup>/<hash-prefix>/<hash>` to a caller-specified directory, renaming it to the original filename. Missing files raise `BackupError.fileCopy` so callers can handle partial exports gracefully.
- Location messages reuse the same mechanism while also surfacing `ZLATITUDE`/`ZLONGITUDE`; video/audio messages add `ZMOVIEDURATION` as `seconds`.

### Profile Photo Retrieval

- Chat/contact avatars live in `Media/Profile/<identifier>-<timestamp>.{jpg,thumb}`. `fetchChatPhotoFilename` looks up the newest file via `FileUtils.latestFile` and copies it to the destination directory as `chat_<chatId>.ext`.
- Contact exports (`copyContactMedia`) follow the same pattern, naming files after the contact phone number. If no entry is found, the photo filename remains `nil` and the API logs a debug message.

## Error Reporting

The library surfaces granular error enums so consumers can react appropriately:

- `BackupError` – issues while scanning or copying from the iTunes backup (e.g. missing Manifest.db, copy failure).
- `DatabaseErrorWA` – database connection problems, unexpected schemas, or missing rows.
- `DomainError` – higher-level logic errors (media not found, unsupported message types).

These errors are thrown from API entry points (`getBackups`, `connectChatStorageDb`, `getChat`, etc.) and are covered by the happy-path tests; you can trigger them manually by corrupting the fixture or requesting unsupported resources.

## Test Coverage

Key tests that exercise the database assumptions:

- `testGetChats` – Validates counts of active/archived sessions read from `ZWACHATSESSION`.
- `testChatMessages` – Iterates every chat, asserting message totals per type and confirming that `MessageInfo` mirrors `ZWAMESSAGE` counters.
- `testMessageContentExtraction` – Spot-checks individual messages (text, link, document, status) to confirm sender resolution, reply chains, filenames, reactions, and status-sync wording.
- `testChatContacts` – Uses `ZWAVCARDMENTION` and profile media lookups to ensure contact export logic matches the fixture (current expectation failures highlight when the dataset evolves).

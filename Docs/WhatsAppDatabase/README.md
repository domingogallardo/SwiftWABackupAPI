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

### Status (`ZMESSAGETYPE = 10`) Subcodes

Every status message includes a non-null `ZGROUPEVENTTYPE`. The implementation currently recognises:

- `38` – Business chat announcements, surfaced as the fixed text `"This is a business chat"`.
- `2` – Status synchronisation events. If `ZTEXT` is empty, the API emits `"Status sync from …"` using the best available sender detail (display name, phone, or JID).

Other subcodes (1, 5, 6, 13, 14, 21, 22, 25, 26, 29, 30, 31, 34, 40, 41, 56, 58) are present in the database but currently fall back to the raw `ZTEXT` (often empty). Extending the mapping for those codes is a known improvement area.

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

## Media Resolution Rules

- Media filenames are resolved through `IPhoneBackup.fetchWAFileHash` and copied with `MediaCopier`. Missing files record an error string in `MessageInfo.error` instead of throwing.
- Location messages combine media copying with coordinate extraction; videos/audio add duration; contact messages rely on vCard metadata and may not expose a filename.

## Test Coverage

Key tests that exercise the database assumptions:

- `testGetChats` – Validates counts of active/archived sessions read from `ZWACHATSESSION`.
- `testChatMessages` – Iterates every chat, asserting message totals per type and confirming that `MessageInfo` mirrors `ZWAMESSAGE` counters.
- `testMessageContentExtraction` – Spot-checks individual messages (text, link, document, status) to confirm sender resolution, reply chains, filenames, and the new status sync wording.
- `testChatContacts` – Uses `ZWAVCARDMENTION` and profile media lookups to ensure contact export logic matches the fixture (current expectation failures highlight when the dataset evolves).

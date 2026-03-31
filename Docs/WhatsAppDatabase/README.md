# WhatsApp Database Reference

This project works against the `ChatStorage.sqlite` database extracted from an iOS backup of WhatsApp. The behaviour described here is derived from the current implementation under `Sources/SwiftWABackupAPI` and is continuously verified by the local private regression suite maintained alongside the project.

## Source of Truth

The observations below come from two places:

- Source files under `Sources/SwiftWABackupAPI`, particularly `SwiftWABackupAPI.swift`, `Message.swift`, `MediaItem.swift`, and supporting helpers.
- A local private fixture database plus accompanying regression tests that exercise the API end-to-end.

When upgrading WhatsApp versions or altering the fixture, re-run the private regression suite and update this document with any schema or mapping changes you observe.

For an audit of which claims in this README are externally corroborated versus fixture-local, see [ExternalValidationMatrix.md](./ExternalValidationMatrix.md).

## LID Terminology

`@lid` is a WhatsApp identifier form seen in modern multi-device contexts. Public reverse-engineering sources describe these as privacy-preserving linked-device-style identifiers rather than ordinary phone-number JIDs. This project treats them as non-phone identifiers that may sometimes be resolved back to a phone number using local client caches such as LID.sqlite.

So, in the API model:

- `@s.whatsapp.net` means the participant is already identified by phone-based JID.
- `@lid` means the participant is identified by a linked/private WhatsApp identity that may or may not be resolvable to a phone number from local client data.

## Core Tables and Columns

| Table | Purpose | Key Columns Used |
| --- | --- | --- |
| `ZWAMESSAGE` | Stores every chat message and system event. | `Z_PK`, `ZCHATSESSION`, `ZMESSAGETYPE`, `ZGROUPEVENTTYPE`, `ZTEXT`, `ZMEDIAITEM`, `ZPARENTMESSAGE`, `ZISFROMME`, `ZGROUPMEMBER`, `ZMESSAGEDATE`, `ZFROMJID`, `ZTOJID` |
| `ZWACHATSESSION` | Metadata for each chat thread. | `Z_PK`, `ZCONTACTJID`, `ZPARTNERNAME`, `ZLASTMESSAGEDATE`, `ZMESSAGECOUNTER`, `ZSESSIONTYPE`, `ZARCHIVED` |
| `ZWAMEDIAITEM` | Metadata for media attached to messages. | `Z_PK`, `ZMEDIALOCALPATH`, `ZTITLE`, `ZMOVIEDURATION`, `ZLATITUDE`, `ZLONGITUDE`, `ZMETADATA` |
| `ZWAGROUPMEMBER` | Group participant roster used to resolve sender info. | `Z_PK`, `ZMEMBERJID`, `ZCONTACTNAME` |
| `ZWAMESSAGEINFO` | Reaction payloads (`ZRECEIPTINFO`). | `ZMESSAGE`, `ZRECEIPTINFO` |

All schema checks live in `DatabaseHelpers.swift` and `DatabaseProtocols.swift`; each model declares the minimal column set that the package expects to find.

## Message Type Mapping

`ZMESSAGETYPE` is converted into the following enum in `SwiftWABackupAPI.swift`:

| Code | Description | Notes |
| --- | --- | --- |
| 0 | Text | Plain messages; text preserved in `ZTEXT`. |
| 1 | Image | Copies media to disk when requested and exposes filename. |
| 2 | Video | Adds filename and duration (`ZMOVIEDURATION`). |
| 3 | Audio | Adds filename and duration. |
| 4 | Contact | Classified as `Contact`, but the current runtime does not expose a validated structured vCard payload. |
| 5 | Location | Emits latitude/longitude (`ZLATITUDE`, `ZLONGITUDE`). |
| 7 | Link | Keeps URL text and optional caption. |
| 8 | Document | Exposes original file name and caption. |
| 10 | Status | System/business events; see subcodes below. |
| 11 | GIF | Treated like video, stored as MP4 in the backup. |
| 15 | Sticker | Returns `.webp` filename. |

The private regression suite verifies that the counts for each supported type are stable against the fixture (currently 5281 images, 489 videos, and 264 status messages).

## Type-By-Type Runtime Matrix

This table focuses on what the current implementation actually validates and exports, not on hypotheses from older reverse-engineering notes.

| Type | Primary discriminator | Extra fields consulted | Current API output | Notes / open questions |
| --- | --- | --- | --- | --- |
| `Text` | `ZMESSAGETYPE = 0` | `ZTEXT` | `message` text plus cross-cutting fields such as `author`, `replyTo`, and `reactions` | Straightforward case. |
| `Image` | `ZMESSAGETYPE = 1` | `ZMEDIAITEM`, `ZWAMEDIAITEM.ZMEDIALOCALPATH`, `ZWAMEDIAITEM.ZTITLE` | `mediaFilename`, optional `caption` | Media copy depends on the backup manifest lookup succeeding. |
| `Video` | `ZMESSAGETYPE = 2` | Image fields plus `ZWAMEDIAITEM.ZMOVIEDURATION` | `mediaFilename`, optional `caption`, optional `seconds` | Duration is only surfaced for `Video` and `Audio`. |
| `Audio` | `ZMESSAGETYPE = 3` | `ZMEDIAITEM`, `ZWAMEDIAITEM.ZMEDIALOCALPATH`, `ZWAMEDIAITEM.ZMOVIEDURATION` | `mediaFilename`, optional `seconds` | Audio captions are rare, but `caption` may still be populated from `ZTITLE` if present. |
| `Contact` | `ZMESSAGETYPE = 4` | `ZTEXT`, optional `ZMEDIAITEM` if present | Generic `MessageInfo` with `messageType = "Contact"` | No validated structured contact payload is currently exposed. |
| `Location` | `ZMESSAGETYPE = 5` | `ZMEDIAITEM`, `ZWAMEDIAITEM.ZLATITUDE`, `ZWAMEDIAITEM.ZLONGITUDE` | `latitude`, `longitude`, optional media/caption fields | Missing coordinates currently fall back to `0.0`, which may hide absent data. |
| `Link` | `ZMESSAGETYPE = 7` | Primarily `ZTEXT`; optional `ZMEDIAITEM` / `ZTITLE` | Link text in `message`, optional `caption` | URL, preview metadata, and preview image are not modeled separately. |
| `Document` | `ZMESSAGETYPE = 8` | `ZMEDIAITEM`, `ZWAMEDIAITEM.ZMEDIALOCALPATH`, `ZWAMEDIAITEM.ZTITLE` | `mediaFilename`, optional `caption` | MIME type and document metadata are not currently surfaced. |
| `Status` | `ZMESSAGETYPE = 10` | `ZGROUPEVENTTYPE`, `ZTEXT`, `ZFROMJID`, `ZISFROMME`, resolved participant identity | Normalized `message`, optional `eventActor`, and usually no `author` | This is the most heuristic-driven family and the one with the most unfinished subcodes. |
| `GIF` | `ZMESSAGETYPE = 11` | Same media fields as `Video` | `mediaFilename`, optional `caption` | Stored like media, but no duration is currently exposed for GIFs. |
| `Sticker` | `ZMESSAGETYPE = 15` | `ZMEDIAITEM`, `ZWAMEDIAITEM.ZMEDIALOCALPATH` | `mediaFilename` | Sticker-specific metadata is not modeled; output is essentially filename + common fields. |

Cross-cutting enrichments that may apply to many rows regardless of their type:

- `author` is reserved for real authored messages and combines `ZISFROMME`, `ZGROUPMEMBER`, `ZFROMJID`, `ZWAGROUPMEMBER`, `ZWACHATSESSION`, `ZWAPROFILEPUSHNAME`, and, when available, the WhatsApp `LID.sqlite` account cache.
- `eventActor` is used for system/status rows that refer to a participant but do not represent a conventional authored message.
- `replyTo` is resolved from `ZWAMESSAGE.ZPARENTMESSAGE` when present, otherwise from `ZMEDIAITEM` plus the binary blob stored in `ZWAMEDIAITEM.ZMETADATA`.
- `reactions` come from `ZWAMESSAGEINFO.ZRECEIPTINFO`.
- `mediaFilename` always requires a second lookup into the iTunes backup manifest to resolve the hashed file path.

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

## Message Identity Resolution

When building `MessageInfo`, the API first resolves a participant identity candidate and then decides whether that identity belongs in `author` or `eventActor`.

### Real Author (`author`)

`author` is used only for rows treated as real user-authored messages:

1. **Outgoing messages (`ZISFROMME = 1`)** – Exposed as `MessageAuthor(kind: .me, displayName: "Me", source: .owner)`.
2. **Group chats** – `ZWAMESSAGE.ZGROUPMEMBER` is used first:
   - `ZWAGROUPMEMBER.ZMEMBERJID` provides the strongest participant identifier.
   - The display name is resolved using a quality-aware priority, not a blind table order:
     - a human-friendly 1:1/contact label from `ZWACHATSESSION.ZPARTNERNAME` is preferred when it is a real name
     - a WhatsApp-only push name from `ZWAPROFILEPUSHNAME` is preferred over phone-only fallback labels and is surfaced with the familiar `~` prefix
     - a phone-only `ZWACHATSESSION.ZPARTNERNAME` or `ZWAGROUPMEMBER.ZCONTACTNAME` is treated as fallback, not as a better label than a human-readable push name
     - `phone` is exposed when the runtime can resolve a real phone confidently from the address book, a linked phone JID, or WhatsApp's `LID.sqlite`; ambiguous `@lid` identities still keep the visible name but leave `phone` unset
   - The runtime strips bidi control characters from display labels so values such as `‎Tú` are exposed cleanly.
   - If `ZGROUPMEMBER` is missing, the runtime falls back to `ZWAMESSAGE.ZFROMJID`.
3. **Individual chats** – `ZCHATSESSION` points to `ZWACHATSESSION`, which supplies the participant JID and display name for incoming messages.

For non-status rows, that resolved identity becomes `MessageInfo.author`.

### Event Participant (`eventActor`)

For status/system rows (`ZMESSAGETYPE = 10`), the same participant-resolution machinery may instead populate `MessageInfo.eventActor`.

This is used when the row appears to be an event associated with a participant, rather than a conventional authored chat message. Examples include sync-style notifications or group-status events.

Important consequences:

- `author` is commonly `nil` for `Status` rows, even when a participant can still be associated with the event.
- `eventActor` is only exposed when the resolved identity appears meaningful as a participant identity.
- If the only fallback identity is a group JID, the runtime currently suppresses `eventActor` instead of pretending that the group identifier is a creator phone.

This behaviour lives in `WABackup+Messages.swift` (`resolveParticipantIdentity`, `resolvedAuthor`, `resolvedEventActor`, `makeParticipantAuthor`) and is covered by the invariant and regression suites.

### WhatsApp Web Alignment Notes

The current display-name strategy has been validated with WhatsApp Web:

- Human-friendly saved/direct-chat labels are preferred over weaker alternatives when they exist.
- Human-readable push names can outrank phone-only fallback labels for group-message authors.
- Unsaved group participants can appear as `~ Name` with secondary phone text, which matches the current `pushName`, `pushNamePhoneJid`, and `lidAccount` strategy.
- Saved-contact cases can appear as bare human names with no visible phone on the label, which matches the current `addressBook` and human-friendly `chatSession` branches.
- Direct/self-chat UI values such as `ZWACHATSESSION.ZPARTNERNAME = '\u200eTú'` are rendered without exposing the bidi control character.

## Reply Resolution

Replies are encoded through media metadata rather than a direct foreign key:

1. If `ZWAMESSAGE.ZPARENTMESSAGE` is populated, the runtime uses it directly as the replied-to message ID.
2. Otherwise, `ZWAMESSAGE.ZMEDIAITEM` may reference a `ZWAMEDIAITEM` row whose `ZMETADATA` holds a protobuf-style blob. Messages without either source keep `replyTo = nil`.
3. `MediaItem.extractReplyStanzaId()` first parses the modern top-level protobuf field that carries the quoted message stanza ID. The historical marker-based heuristic is kept as a backward-compatible fallback for older fixture blobs.
4. `WABackup.fetchReplyMessageId` uses `Message.fetchMessageId(byStanzaId:)` to locate the original `ZWAMESSAGE.Z_PK`.
5. If found, `MessageInfo.replyTo` contains the target message ID; otherwise it remains `nil`.

`SwiftWABackupAPITests.testMessageContentExtraction` exercises this behaviour, and the current implementation has also been checked against WhatsApp Web. It resolves modern quoted replies that are visibly rendered there while still preserving compatibility with the older fixture format.

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
- `testChatContacts` – Validates aggregate contact counts and profile media lookups against the fixture.

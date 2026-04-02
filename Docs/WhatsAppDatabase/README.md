# WhatsApp Database Reference

This project works against the `ChatStorage.sqlite` database extracted from an iOS backup of WhatsApp. The behaviour described here is derived from the current implementation under `Sources/SwiftWABackupAPI` and is continuously verified by the local private regression suite maintained alongside the project.

## Source of Truth

The observations below come from two places:

- Source files under `Sources/SwiftWABackupAPI`, particularly `SwiftWABackupAPI.swift`, `Message.swift`, `MediaItem.swift`, and supporting helpers.
- A local private fixture database plus accompanying regression tests that exercise the API end-to-end.

When upgrading WhatsApp versions or altering the fixture, re-run the private regression suite and update this document with any schema or mapping changes you observe.

For an audit of which claims in this README are externally corroborated versus fixture-local, see [ExternalValidationMatrix.md](./ExternalValidationMatrix.md).

## LID Terminology

`@lid` is a WhatsApp identifier form seen in modern multi-device contexts. Public sources consistently describe it as a non-phone identifier, but they do not agree on a single authoritative expansion of the acronym. This project therefore treats `LID` as an opaque WhatsApp term and treats `@lid` identities as distinct from ordinary phone-number JIDs. When local client caches such as `LID.sqlite` are available, the runtime may sometimes resolve a `@lid` identity back to a phone number.

So, in the API model:

- `@s.whatsapp.net` means the participant is already identified by phone-based JID.
- `@lid` means the participant is identified by a non-phone/private WhatsApp identity that may or may not be resolvable to a phone number from local client data.

## Core Tables and Columns

| Table | Purpose | Key Columns Used |
| --- | --- | --- |
| `ZWAMESSAGE` | Stores WhatsApp message rows. | `Z_PK`, `ZCHATSESSION`, `ZMESSAGETYPE`, `ZTEXT`, `ZMEDIAITEM`, `ZPARENTMESSAGE`, `ZISFROMME`, `ZGROUPMEMBER`, `ZMESSAGEDATE`, `ZFROMJID`, `ZTOJID` |
| `ZWACHATSESSION` | Metadata for each chat thread. | `Z_PK`, `ZCONTACTJID`, `ZPARTNERNAME`, `ZLASTMESSAGEDATE`, `ZMESSAGECOUNTER`, `ZSESSIONTYPE`, `ZARCHIVED` |
| `ZWAMEDIAITEM` | Metadata for media attached to messages. | `Z_PK`, `ZMEDIALOCALPATH`, `ZTITLE`, `ZMOVIEDURATION`, `ZLATITUDE`, `ZLONGITUDE`, `ZMETADATA` |
| `ZWAGROUPMEMBER` | Group participant roster used to resolve sender info. | `Z_PK`, `ZMEMBERJID`, `ZCONTACTNAME` |
| `ZWAMESSAGEINFO` | Reaction payloads (`ZRECEIPTINFO`). | `ZMESSAGE`, `ZRECEIPTINFO` |

All schema checks live in `DatabaseHelpers.swift` and `DatabaseProtocols.swift`; each model declares the minimal column set that the package expects to find.

## Message Type Mapping

The public API maps `ZMESSAGETYPE` into the following supported message families:

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
| 11 | GIF | Validated against WhatsApp Web examples as GIF-style media; stored as MP4 in the backup. |
| 15 | Sticker | Validated against WhatsApp Web examples as sticker-style media; typically returns a `.webp` filename. |

## Type-By-Type Runtime Matrix

This table focuses on what the current implementation actually validates and exports, not on hypotheses from older reverse-engineering notes.

| Type | Primary discriminator | Extra fields consulted | Current API output | Notes / open questions |
| --- | --- | --- | --- | --- |
| `Text` | `ZMESSAGETYPE = 0` | `ZTEXT` | `message` text plus cross-cutting fields such as `author`, `replyTo`, and `reactions` | Straightforward case. |
| `Image` | `ZMESSAGETYPE = 1` | `ZMEDIAITEM`, `ZWAMEDIAITEM.ZMEDIALOCALPATH`, `ZWAMEDIAITEM.ZTITLE` | `mediaFilename`, optional `caption` | Media copy depends on the backup manifest lookup succeeding. |
| `Video` | `ZMESSAGETYPE = 2` | Image fields plus `ZWAMEDIAITEM.ZMOVIEDURATION` | `mediaFilename`, optional `caption`, optional `seconds` | Duration is only surfaced for `Video` and `Audio`. |
| `Audio` | `ZMESSAGETYPE = 3` | `ZMEDIAITEM`, `ZWAMEDIAITEM.ZMEDIALOCALPATH`, `ZWAMEDIAITEM.ZMOVIEDURATION` | `mediaFilename`, optional `seconds` | Audio captions are rare, but `caption` may still be populated from `ZTITLE` if present. |
| `Contact` | `ZMESSAGETYPE = 4` | `ZTEXT`, optional `ZMEDIAITEM` if present | Generic `MessageInfo` with `messageType = "Contact"` | No validated structured contact payload is currently exposed. |
| `Location` | `ZMESSAGETYPE = 5` | `ZMEDIAITEM`, `ZWAMEDIAITEM.ZLATITUDE`, `ZWAMEDIAITEM.ZLONGITUDE` | `latitude`, `longitude`, optional media/caption fields | Missing coordinates remain `nil`, so the API does not silently turn absent data into `0.0, 0.0`. |
| `Link` | `ZMESSAGETYPE = 7` | Primarily `ZTEXT`; optional `ZMEDIAITEM` / `ZTITLE` | Link text in `message`, optional `caption` | URL, preview metadata, and preview image are not modeled separately. |
| `Document` | `ZMESSAGETYPE = 8` | `ZMEDIAITEM`, `ZWAMEDIAITEM.ZMEDIALOCALPATH`, `ZWAMEDIAITEM.ZTITLE` | `mediaFilename`, optional `caption` | MIME type and document metadata are not currently surfaced. |
| `GIF` | `ZMESSAGETYPE = 11` | Same media fields as `Video` | `mediaFilename`, optional `caption` | Validated against WhatsApp Web examples as GIF-style media. Stored like media, but no duration is currently exposed for GIFs. |
| `Sticker` | `ZMESSAGETYPE = 15` | `ZMEDIAITEM`, `ZWAMEDIAITEM.ZMEDIALOCALPATH` | `mediaFilename` | Validated against WhatsApp Web examples as sticker-style media. Sticker-specific metadata is not modeled; output is essentially filename + common fields. |

Cross-cutting enrichments that may apply to many rows regardless of their type:

- `author` combines `ZISFROMME`, `ZGROUPMEMBER`, `ZFROMJID`, `ZWAGROUPMEMBER`, `ZWACHATSESSION`, `ZWAPROFILEPUSHNAME`, and, when available, the WhatsApp `LID.sqlite` account cache.
- `replyTo` is resolved from `ZWAMESSAGE.ZPARENTMESSAGE` when present, otherwise from `ZMEDIAITEM` plus the binary blob stored in `ZWAMEDIAITEM.ZMETADATA`.
- `reactions` come from `ZWAMESSAGEINFO.ZRECEIPTINFO`.
- `mediaFilename` always requires a second lookup into the iTunes backup manifest to resolve the hashed file path.

## Message Identity Resolution

When building `MessageInfo`, the API resolves a single structured participant identity into `author`.

### Real Author (`author`)

`author` is used only for rows treated as real user-authored messages:

1. **Outgoing messages (`ZISFROMME = 1`)** – Exposed as `MessageAuthor(kind: .me, displayName: "Me", source: .owner)`.
2. **Group chats** – `ZWAMESSAGE.ZGROUPMEMBER` is used first:
   - `ZWAGROUPMEMBER.ZMEMBERJID` provides the strongest participant identifier.
   - The current runtime resolves the participant label using this exact order:
     1. a non-phone-like direct-chat/session label from `ZWACHATSESSION.ZPARTNERNAME`
     2. an address-book contact from `ContactsV2.sqlite`
     3. a `LID.sqlite` account match
     4. a linked phone JID plus WhatsApp push-name label
     5. a WhatsApp push name from `ZWAPROFILEPUSHNAME`
     6. a phone-like `ZWACHATSESSION.ZPARTNERNAME`
     7. `ZWAGROUPMEMBER.ZCONTACTNAME` as the last fallback
   - This is intentionally quality-aware rather than a blind table order:
     - a human-friendly saved/direct-chat label is preferred when it is a real name
     - a WhatsApp-only push name is preferred over phone-only fallback labels and is surfaced with the familiar `~` prefix
     - phone-only labels from `ZWACHATSESSION` or `ZWAGROUPMEMBER` are treated as fallback, not as better labels than a human-readable push name
     - `phone` is exposed when the runtime can resolve a real phone confidently from the address book, a linked phone JID, or WhatsApp's `LID.sqlite`; ambiguous `@lid` identities still keep the visible name but leave `phone` unset
   - The runtime strips bidi control characters from display labels so values such as `‎Tú` are exposed cleanly.
   - If `ZGROUPMEMBER` is missing, the runtime falls back to `ZWAMESSAGE.ZFROMJID`.
3. **Individual chats** – `ZCHATSESSION` points to `ZWACHATSESSION`, which supplies the participant JID and display name for incoming messages.

This behaviour lives in `WABackup+Messages.swift` (`resolveParticipantIdentity`, `makeParticipantAuthor`) and is covered by the invariant and regression suites.

### WhatsApp Web Alignment Notes

The current display-name strategy has been validated with WhatsApp Web:

- Human-friendly saved/direct-chat labels are preferred over weaker alternatives when they exist.
- Human-readable push names can outrank phone-only fallback labels for group-message authors.
- Unsaved group participants can appear as `~Name` with secondary phone text, which matches the current `pushName`, `pushNamePhoneJid`, and `lidAccount` strategy.
- Saved-contact cases can appear as bare human names with no visible phone on the label, which matches the current `addressBook` and human-friendly `chatSession` branches.
- Direct/self-chat UI values such as `ZWACHATSESSION.ZPARTNERNAME = '\u200eTú'` are rendered without exposing the bidi control character.
- Some later internal branches remain UI-indistinguishable in practice, so WhatsApp Web validates the visible precedence decisions above without proving every internal branch of the total runtime order.

## Reply Resolution

Replies are encoded through media metadata rather than a direct foreign key:

1. If `ZWAMESSAGE.ZPARENTMESSAGE` is populated, the runtime uses it directly as the replied-to message ID.
2. Otherwise, `ZWAMESSAGE.ZMEDIAITEM` may reference a `ZWAMEDIAITEM` row whose `ZMETADATA` holds a protobuf-style blob. Messages without either source keep `replyTo = nil`.
3. `MediaItem.extractReplyStanzaId()` parses the modern top-level protobuf field that carries the quoted message stanza ID.
4. `WABackup.fetchReplyMessageId` uses `Message.fetchMessageId(byStanzaId:)` to locate the original `ZWAMESSAGE.Z_PK`.
5. If found, `MessageInfo.replyTo` contains the target message ID; otherwise it remains `nil`.

`SwiftWABackupAPITests.testMessageContentExtraction` exercises this behaviour, and the current implementation has also been checked against WhatsApp Web. It resolves modern quoted replies that are visibly rendered there through `ZPARENTMESSAGE` and modern protobuf-style metadata.

## Reaction Storage

- Reactions live in `ZWAMESSAGEINFO.ZRECEIPTINFO` as binary blobs. Entries only exist for messages that received reactions.
- `ReactionParser` now walks the nested protobuf-style receipt entries inside `ZRECEIPTINFO`, extracting the reacting JID and emoji from structured length-delimited fields instead of scanning the blob byte-by-byte.
- The runtime now emits reactions only when that structured metadata identifies both an emoji and a reacting participant JID. Ambiguous legacy blobs without a resolvable participant are ignored rather than guessed.
- `WABackup.fetchReactions` resolves the reacting participant using the same identity sources already used elsewhere in the API, including direct-chat data, address-book data, WhatsApp push names, and `LID.sqlite` for `@lid` identities.
- Parsed reactions become `[Reaction]` values with an `emoji` and a structured `author`, attached to `MessageInfo.reactions`.
- The validated WhatsApp Web examples now line up with the current visible reaction behavior on the checked messages, including emoji plus the reacting participant's label and phone when the web shows one.
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
- `testMessageContentExtraction` – Spot-checks individual messages (text, link, document, and replies/reactions) to confirm sender resolution, reply chains, filenames, and reaction handling.
- `testChatContacts` – Validates aggregate contact counts and profile media lookups against the fixture.

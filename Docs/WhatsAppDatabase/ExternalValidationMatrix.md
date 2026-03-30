# External Validation Matrix

This document audits the claims in [README.md](./README.md) against external sources available as of March 24, 2026.

The goal is not to replace the implementation-focused README, but to separate:

- behaviour that is externally corroborated,
- behaviour that is only partially corroborated,
- behaviour that appears to conflict with older external sources, and
- behaviour that is currently best treated as fixture-local or parser-specific inference.

## Validation Levels

- `Externally corroborated`
  Multiple external sources broadly agree with the README claim.
- `Partially corroborated`
  External sources support part of the claim, but not the exact runtime interpretation.
- `Conflicted / version-sensitive`
  External sources describe a different mapping or a historically older schema variant.
- `Fixture-local / inferred`
  The behaviour is supported by this project's code and private fixture, but not convincingly documented elsewhere.

## Source Catalog

These are the main external references used for the matrix below.

1. [Belkasoft: iOS WhatsApp Forensics with Belkasoft X](https://belkasoft.com/ios-whatsapp-forensics-with-belkasoft-x)
   Practical iOS WhatsApp forensic walkthrough with screenshots and field descriptions for `ZWACHATSESSION`, `ZWAMESSAGE`, and `ZWAMEDIAITEM`.

2. [CERT-XLM / CoRIIN 2020 PDF](https://www.cecyf.fr/wp-content/uploads/2024/05/CoRIIN2020-Smartphone-Whatsapp.pdf)
   Strong external reference for iOS table relationships, relevant columns, group-message correlation, `ZWAMESSAGEINFO`, and the lack of official documentation.

3. [HackTricks: iOS Backup Forensics](https://book.hacktricks.wiki/en/generic-methodologies-and-resources/basic-forensic-methodology/ios-backup-forensics.html)
   Useful for backup reconstruction, `Manifest.db`, hashed backup layout, and the `ZWAMESSAGE` ↔ `ZWAMEDIAITEM` linkage via `ZMEDIALOCALPATH`.

4. [Mobile Verification Toolkit docs: `whatsapp.json`](https://docs.mvt.re/en/stable/ios/records/)
   Independent confirmation that modern tooling extracts WhatsApp records from `ChatStorage.sqlite` under the shared App Group path.

5. [Historical community SQL mapping gist (`convert.sql`)](https://gist.github.com/marmolejo/9f19f7f91ee6e58ec44f)
   Not authoritative, but useful as a historical independent mapping of `ZWAMESSAGE`, `ZWAMEDIAITEM`, `ZWAGROUPMEMBER`, `ZSTANZAID`, and `ZGROUPEVENTTYPE`.

6. [Mobile Forensics Guide for iOS & Android Devices (online excerpt)](https://studylib.net/doc/28056759/moreb-practical-forensic-analysis-of-artifacts-on-ios-and...)
   Secondary source confirming `Media/Profile`, `Message/Media`, `Stickers`, and the existence of `ZWAGROUPMEMBER`-family tables in `ChatStorage.sqlite`.

## Matrix By README Section

### 1. Source of Truth

| README section | Status | Notes |
| --- | --- | --- |
| `Source of Truth` | `Fixture-local / inferred` | This section is intentionally repo-specific. External sources can corroborate the database families, but not the statement that the implementation and private regression suite are the project’s operational source of truth. |

### 2. Core Tables and Columns

| README claim | Status | Notes |
| --- | --- | --- |
| `ZWAMESSAGE` is central and stores message/event rows | `Externally corroborated` | Strongly supported by Belkasoft and CoRIIN. |
| `ZWACHATSESSION` stores chat metadata | `Externally corroborated` | Strongly supported by Belkasoft. |
| `ZWAMEDIAITEM` stores attachment metadata | `Externally corroborated` | Supported by Belkasoft, CoRIIN, and HackTricks. |
| `ZWAGROUPMEMBER` is used to resolve group participants | `Externally corroborated` | Supported by CoRIIN and secondary forensic references. |
| `ZWAMESSAGEINFO` is relevant for message status / extra metadata | `Externally corroborated` | Supported by CoRIIN; exact semantics remain narrower externally than in this project. |
| Exact minimal `expectedColumns` enforced by the code | `Fixture-local / inferred` | This is a project-specific schema contract, not something external sources validate. |

### 3. Message Type Mapping

| README claim | Status | Notes |
| --- | --- | --- |
| Codes `0,1,2,3,4,5,7,8` map to text/image/video/audio/contact/location/url/file | `Externally corroborated` | Belkasoft and CoRIIN both describe this family of mappings. |
| `10` behaves as a status/system family | `Partially corroborated` | Externally, status/system-event behaviour is visible, but subcode semantics remain poorly documented. |
| `11 = GIF` | `Fixture-local / inferred` | I did not find a strong independent source naming `11` specifically as GIF for iOS ChatStorage.sqlite. |
| `15 = Sticker` | `Fixture-local / inferred` | External sources confirm sticker artifacts exist on iOS, but not this exact code mapping in the reviewed sources. |
| The supported enum is complete enough for the API | `Conflicted / version-sensitive` | CoRIIN and Belkasoft both document `ZMESSAGETYPE = 6` as a group-management/event family, while the current API does not expose that code as a supported public type. This may be an intentional design choice, but it is not an externally validated full type map. |

### 4. Type-By-Type Runtime Matrix

| README subsection | Status | Notes |
| --- | --- | --- |
| `Text`, `Image`, `Video`, `Audio`, `Location`, `Link`, `Document` rows | `Partially corroborated` | External sources support the underlying fields, but the exact output shape of `MessageInfo` is of course project-specific. |
| `Contact` row says there is no validated structured contact payload | `Externally corroborated` | This is now the conservative, externally defensible statement. I did not find strong external evidence for a validated modern iOS contact-card parser in this schema. |
| `GIF` row notes media-like handling but no exposed duration | `Fixture-local / inferred` | That exact behaviour is runtime-specific. |
| `Sticker` row notes filename-only style handling | `Fixture-local / inferred` | Again, a runtime behaviour statement rather than something documented externally. |
| Cross-cutting fields `author`, `replyTo`, `reactions`, `mediaFilename` | Mixed | See the dedicated sections below. |

### 5. Status Subcodes

| README claim | Status | Notes |
| --- | --- | --- |
| Subcode table for `ZGROUPEVENTTYPE` under `ZMESSAGETYPE = 10` | `Fixture-local / inferred` | This appears to come primarily from the private fixture plus implementation analysis. External sources reviewed here do not provide a reliable subcode taxonomy. |
| `eventType 38` -> business chat text | `Fixture-local / inferred` | Plausible and tested locally, but not externally corroborated. |
| `eventType 2` -> status sync wording | `Fixture-local / inferred` | Same as above. |
| Other subcodes remain unmapped | `Externally corroborated` in spirit | CoRIIN explicitly notes that various codes remain unidentified in forensic work; the exact list in the README is local. |

### 6. Author Resolution

| README claim | Status | Notes |
| --- | --- | --- |
| Outgoing messages are identified via `ZISFROMME` | `Externally corroborated` | Strongly supported by Belkasoft and CoRIIN. |
| Group authorship involves `ZGROUPMEMBER` and `ZWAGROUPMEMBER` | `Externally corroborated` | Strongly supported by CoRIIN. |
| Individual authorship relies on `ZCHATSESSION` / `ZWACHATSESSION` | `Partially corroborated` | Externally consistent, though the exact way the API collapses this into `MessageAuthor` is project-specific. |
| Priority order `chatSession > pushName > groupMember > messageJid` | `Fixture-local / inferred` | This ordering is a deliberate parser policy, not something external sources describe. |
| Fallback from missing `ZGROUPMEMBER` to `ZFROMJID` | `Partially corroborated` | `ZFROMJID` is externally documented as relevant, but the fallback strategy itself is local. |
| Separating a real `author` from an `eventActor` for status/system rows | `Fixture-local / inferred` | This is an explicit project-level interpretation to avoid overstating authorship on system rows. It is consistent with the database patterns observed in the fixture, but external sources do not define this distinction. |

### 7. Reply Resolution

| README claim | Status | Notes |
| --- | --- | --- |
| Replies are not exposed through a simple foreign key | `Partially corroborated` | External sources agree that multiple tables/blobs must often be correlated, but do not document a canonical reply field for modern iOS WhatsApp. |
| Reply extraction from `ZWAMEDIAITEM.ZMETADATA` | `Fixture-local / inferred` | I did not find a strong independent source documenting this exact protobuf-style extraction logic. |
| Resolving the target via `ZSTANZAID` | `Partially corroborated` | Historical community SQL mappings use `ZSTANZAID`, but the exact reply workflow remains mostly local knowledge. |

### 8. Reaction Storage

| README claim | Status | Notes |
| --- | --- | --- |
| `ZWAMESSAGEINFO` and `ZRECEIPTINFO` are important | `Externally corroborated` | CoRIIN explicitly documents `ZWAMESSAGEINFO` and `ZRECEIPTINFO`. |
| `ZRECEIPTINFO` stores emoji reactions as parsed by `ReactionParser` | `Partially corroborated` | This project has strong local evidence, but reviewed external sources more often describe `ZRECEIPTINFO` as delivery/read status information, especially for groups. The exact reaction encoding should therefore be treated as version-sensitive and parser-inferred. |
| The current byte parser is a stable general solution | `Fixture-local / inferred` | There is no convincing external documentation for the exact blob format across app versions. |

### 9. Media Retrieval and Manifest Lookup

| README claim | Status | Notes |
| --- | --- | --- |
| WhatsApp files live under the shared App Group path in iOS backups | `Externally corroborated` | Strongly supported by Belkasoft, HackTricks, MVT, and other forensic references. |
| `Manifest.db` maps hashed backup objects back to logical paths | `Externally corroborated` | Strongly supported by HackTricks and general iOS backup methodology. |
| `ZMEDIALOCALPATH` is the key field linking message rows to media paths | `Externally corroborated` | Strongly supported by Belkasoft, CoRIIN, and HackTricks. |
| The exact domain string `AppDomainGroup-group.net.whatsapp.WhatsApp.shared` | `Externally corroborated` | Strongly supported by Belkasoft and multiple modern references. |
| The project’s file-copying policy and filename conventions | `Fixture-local / inferred` | This is implementation behaviour rather than external database knowledge. |

### 10. Profile Photo Retrieval

| README claim | Status | Notes |
| --- | --- | --- |
| WhatsApp profile media exists under `Media/Profile/` | `Externally corroborated` | Supported by secondary forensic references and tooling guidance. |
| Selecting the newest file by timestamp-like suffix | `Fixture-local / inferred` | This is a local heuristic. |
| Naming exported files `chat_<chatId>.ext` or `<phone>.ext` | `Fixture-local / inferred` | Purely project-specific export policy. |

### 11. Error Reporting

| README claim | Status | Notes |
| --- | --- | --- |
| Error enums `BackupError`, `DatabaseErrorWA`, `DomainError` | `Fixture-local / inferred` | These are internal library constructs and do not require external validation. |

### 12. Test Coverage

| README claim | Status | Notes |
| --- | --- | --- |
| Regression and invariant tests validate the described behaviour | `Fixture-local / inferred` | This is true by inspection of the repo, but it is not an external-validation topic. |

## Practical Conclusions

The README is strongest, from an external-validation perspective, in these areas:

- the overall iOS storage location and backup domain,
- the importance of `ZWAMESSAGE`, `ZWACHATSESSION`, `ZWAMEDIAITEM`, `ZWAGROUPMEMBER`, and `ZWAMESSAGEINFO`,
- the broad meaning of common message types such as text/image/video/audio/location/url/file,
- the need to correlate multiple tables to understand group chats and media.

The README should be treated more cautiously in these areas:

- exact completeness of the message-type enum,
- detailed `Status` subcode meanings,
- reply extraction from `ZMETADATA`,
- the exact semantics of `ZRECEIPTINFO` as emoji reactions rather than only delivery/read status,
- the precise precedence rules used to resolve `MessageAuthor`.

## Recommended Documentation Policy

For future edits to [README.md](./README.md), I recommend this rule:

- keep externally corroborated schema facts in the main README,
- keep parser heuristics and fixture-driven interpretations explicitly labeled as such,
- keep version-sensitive findings in dated tables,
- and record any claim that lacks an external source as `observed in local fixture` rather than as an objective schema fact.

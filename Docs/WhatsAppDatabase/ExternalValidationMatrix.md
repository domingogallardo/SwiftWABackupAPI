# External Validation Report for `SwiftWABackupAPI` README  
**Scope:** validation of the supplied README claims **without using the `SwiftWABackupAPI` repository**.

## Methodology

I validated the README against external sources only, prioritizing public forensic write-ups, reverse-engineering references, official WhatsApp/GitHub material where available, and independent public code/examples. I **did not use the `SwiftWABackupAPI` repository** in this pass.

Because WhatsApp does not publish an official schema reference for `ChatStorage.sqlite`, some claims can only be checked against third-party reverse-engineering sources. For that reason, the labels below mean:

- **`externally corroborated`**: supported by one or more external sources and not materially contradicted by stronger external evidence.
- **`externally conflicted`**: public external sources disagree in a material way, or the public evidence points in more than one direction.
- **`WA-Web-validated`**: not externally documented in strong public sources, but validated against the visible behavior of real WhatsApp Web sessions and screenshots.
- **`fixture-only`**: I found no sufficiently strong external corroboration; the claim appears to depend on your implementation, your fixture, or local reverse engineering.

## Validation matrix

| README claim / area | Verdict | Notes |
|---|---|---|
| The project works against `ChatStorage.sqlite` extracted from an iOS WhatsApp backup. | `externally corroborated` | Multiple forensic references identify `ChatStorage.sqlite` as the main WhatsApp message database on iOS / iTunes-Finder backups. [1][2][3] |
| The WhatsApp backup domain/path is `AppDomainGroup-group.net.whatsapp.WhatsApp.shared`. | `externally corroborated` | External forensic references and public extraction code use that exact app-group domain when locating `ChatStorage.sqlite` and related files. [2][4] |
| `ZWAMESSAGE`, `ZWACHATSESSION`, and `ZWAMEDIAITEM` are core tables for iOS WhatsApp analysis. | `externally corroborated` | This is directly described in forensic references. [1][2] |
| `ZWAMESSAGEINFO` exists and links to messages via `ZMESSAGE`; `ZRECEIPTINFO` is a blob field of interest. | `externally corroborated` | Independent public SQL/examples reference `ZWAMESSAGEINFO.ZRECEIPTINFO`, and reverse-engineering discussions mention the blob explicitly. [5][6] |
| `ZWAGROUPMEMBER` is used to resolve senders in group chats. | `externally corroborated` | Public migration/conversion SQL joins `ZWAMESSAGE.ZGROUPMEMBER` to `ZWAGROUPMEMBER.Z_PK` and uses `ZMEMBERJID` for sender identity in groups. [7][8] |
| `ZWAMESSAGE` columns such as `ZCHATSESSION`, `ZMESSAGETYPE`, `ZTEXT`, `ZMEDIAITEM`, `ZISFROMME`, `ZGROUPMEMBER`, `ZMESSAGEDATE`, `ZFROMJID`, and `ZTOJID` are central to extraction. | `externally corroborated` | These fields are described in forensic references and appear in public SQL/scripts for iOS backups. [1][2][5] |
| `ZWACHATSESSION` columns such as `ZCONTACTJID`, `ZPARTNERNAME`, `ZLASTMESSAGEDATE`, `ZMESSAGECOUNTER`, `ZSESSIONTYPE`, and archive-related metadata are relevant chat metadata. | `externally corroborated` | Public forensic documentation describes the main purpose of these fields and the conversation/session role of the table. [1][2] |
| `ZWAMEDIAITEM` columns such as `ZMEDIALOCALPATH`, `ZTITLE`, `ZMOVIEDURATION`, `ZLATITUDE`, `ZLONGITUDE`, and media metadata fields are used for attachment extraction. | `externally corroborated` | External sources describe these columns and their general purpose. [1][5][7] |
| `ZMESSAGETYPE` basic mapping for `0=text`, `1=image`, `2=video`, `3=voice/audio`, `4=contact`, `5=location`, `7=URL/link`, `8=file/document` is valid. | `externally corroborated` | Belkasoft and another database-forensics reference give essentially that mapping. [1][9] |
| Extended message-type mapping in the README (`10=Status`, `11=GIF`, `15=Sticker`) is established externally as written. | `externally conflicted` | I did **not** find strong authoritative documentation for this exact extended mapping. Worse, public reverse-engineering sources are inconsistent: one recent public source maps sticker/GIF/deletion-related values differently (`8=sticker`, `13=GIF`, `15=deleted for everyone`). This makes the exact higher-value mapping version-dependent and publicly inconsistent. [10][11] |
| The status subcode table for `ZMESSAGETYPE = 10` (`ZGROUPEVENTTYPE` values, counts, and English renderings such as `This is a business chat` or `Status sync from …`) is externally documented. | `fixture-only` | I found public evidence that system/group/control messages exist, but not reliable external documentation for your exact subcode meanings, counts, or normalization strings. |
| The fixture counts (for example `5281` images, `489` videos, `264` status messages) can be externally validated. | `fixture-only` | These are local fixture facts, not public facts. |
| `@lid` identifiers are non-phone identifiers that appear in modern multi-device WhatsApp contexts. | `externally corroborated` | External discussions and tool ecosystems consistently describe `@lid` as a non-phone identifier introduced by newer WhatsApp multi-device / privacy-preserving behavior. [12][13][14] |
| `@s.whatsapp.net` is the phone-based JID form, while `@lid` is a linked/private identifier that may need local mapping. | `externally corroborated` | External issue reports and release notes describe both forms and the need to resolve between them. [12][13][15] |
| A local cache/database such as `LID.sqlite` may exist and help with LID resolution. | `externally corroborated` | External references show `LID.sqlite` present in WhatsApp-related backups/exfiltration targets, which supports the existence of such a cache/database. [16][17] |
| The likely expansion of **LID** as `Linked ID` or `Link ID` is established externally. | `externally conflicted` | Public sources are inconsistent here. Some external tool vendors or project release notes call it **Linked ID**, while other public discussions describe the same identifiers as **linked device IDs** or simply as privacy-preserving local/linked identifiers. I did not find an authoritative WhatsApp source standardizing the expansion. [12][15][18] |
| Author resolution using `ZISFROMME`, `ZWAGROUPMEMBER`, `ZWACHATSESSION`, `ZWAPROFILEPUSHNAME`, and optional LID mapping is plausible. | `externally corroborated` | The underlying tables/fields used in your reasoning are externally documented. The exact logic is your implementation, but the data sources you rely on are externally real. [1][2][5][8] |
| The visible sender-label behavior seen in WhatsApp Web, including `~` prefix display and the fact that bidi control characters are not surfaced to the user, matches the API's current normalization strategy. | `WA-Web-validated` | Validated against real WhatsApp Web screenshots. Example: `ZWACHATSESSION.ZPARTNERNAME = '\\u200eTú'` is shown in the UI without exposing the leading LRM, and group-message screenshots show clean `~ Name` labels and `+34 ...` phone strings rather than raw bidi-wrapped database values. |
| The exact author-resolution priority order (`ZPARTNERNAME` → `ZWAPROFILEPUSHNAME` → `ZWAGROUPMEMBER.ZCONTACTNAME`) is externally established WhatsApp behavior. | `externally conflicted` | WhatsApp Web evidence now conflicts with the order as written. In one validated group chat, the web prefers a human-friendly saved/direct-chat label over a more formal conflicting `ZWAPROFILEPUSHNAME` and over a phone-only `ZWAGROUPMEMBER.ZCONTACTNAME`. But another validated group chat shows the opposite of the documented order for phone-only chat-session labels: a phone-only `ZPARTNERNAME` and `ZWAGROUPMEMBER.ZCONTACTNAME` lose to a human-readable `ZWAPROFILEPUSHNAME`, and the web visibly renders the `~ Name` push label. |
| In WhatsApp Web group-message rendering, a human-friendly push name can outrank phone-only fallback labels coming from direct-chat/session or group-member records. | `WA-Web-validated` | Validated against real WhatsApp Web screenshots. In one validated group chat, the database stores phone-only fallback labels in both `ZWACHATSESSION.ZPARTNERNAME` and `ZWAGROUPMEMBER.ZCONTACTNAME`, while the web visibly renders a `~ Name` label from `ZWAPROFILEPUSHNAME`. |
| `author` versus `eventActor` as separate semantic outputs is externally documented WhatsApp behavior. | `WA-Web-validated` | Real WhatsApp Web screenshots support the visible distinction even though the exact field split is still your API model. Ordinary group messages render a sender label above the bubble, while system rows render as center/system content or search-result snippets with the participant embedded in the text rather than exposed as a normal message author. That makes the `author` versus `eventActor` separation a good fit for observed UI behavior. |
| The visible quoted-reply behavior rendered by WhatsApp Web matches the API's current `replyTo` output on validated examples. | `WA-Web-validated` | Validated against real WhatsApp Web screenshots and current local API output. Recent quoted replies visibly rendered in the UI now resolve correctly through the API's `replyTo` field, while ordinary non-quoted messages in the same validated views continue to expose `replyTo = nil`. |
| The exact legacy fallback byte markers used for reply parsing inside `ZWAMEDIAITEM.ZMETADATA` (`0x32 0x1A` / `0x9A 0x01`) are externally documented. | `fixture-only` | I still found no strong external documentation for those exact markers or for the historical stanza-ID extraction heuristic. The current runtime no longer depends on that heuristic alone, because it first checks `ZWAMESSAGE.ZPARENTMESSAGE` and then parses the modern protobuf-style reply metadata, but the legacy marker fallback remains an implementation detail grounded mainly in fixture behavior. |
| Reactions are stored in `ZWAMESSAGEINFO.ZRECEIPTINFO` as binary blobs. | `externally corroborated` | The existence of `ZRECEIPTINFO` as a blob is externally corroborated; it is publicly recognized as opaque receipt-related metadata. [5][6] |
| Your specific `ReactionParser` algorithm (emoji length byte + UTF-8 slice + preceding JID bytes) is externally established. | `fixture-only` | I found no strong external confirmation for that exact blob format/parser. |
| Media retrieval via iOS `Manifest.db` / `Files(fileID, domain, relativePath)` and then locating the hashed file under `<backup>/<prefix>/<fileID>` is the correct general model. | `externally corroborated` | This is standard iOS backup behavior and is also reflected in public WhatsApp extraction code. [4][19][20] |
| Looking up WhatsApp media by `domain = 'AppDomainGroup-group.net.whatsapp.WhatsApp.shared'` plus relative path is externally grounded. | `externally corroborated` | Public code that extracts WhatsApp data from iPhone backups uses exactly that approach. [4] |
| Profile photos / avatars in WhatsApp iOS data are found under `Media/Profile/`. | `externally corroborated` | Group-IB explicitly lists `/Media/Profile/` for contact/group thumbnails and avatars, and independent training material repeats the same location. [2][21] |
| Sticker assets are associated with `.webp` files. | `externally corroborated` | Group-IB notes a `/stickers/` directory in the shared container, and official WhatsApp sticker documentation for iOS states that sticker payloads use WebP data. [2][22] |
| The exact export naming rules in your README for avatars (for example `chat_<chatId>.ext`, newest-file selection, phone-based contact filenames) are externally documented. | `fixture-only` | The directory is externally corroborated, but your export-naming convention is implementation-specific. |
| The error taxonomy (`BackupError`, `DatabaseErrorWA`, `DomainError`) is externally grounded in the WhatsApp data model. | `fixture-only` | Those are library/API design choices, not public WhatsApp artifacts. |
| The listed tests (`testGetChats`, `testChatMessages`, `testMessageContentExtraction`, `testChatContacts`) provide external evidence. | `fixture-only` | They are internal validation assets unless reproduced and independently audited from outside the project. |

## Overall assessment

### Strongly supported externally

The README is on firm ground in its **high-level forensic model**:

- `ChatStorage.sqlite` is the central iOS message database.
- The app-group domain/path is correct.
- The main tables (`ZWAMESSAGE`, `ZWACHATSESSION`, `ZWAMEDIAITEM`, `ZWAMESSAGEINFO`, `ZWAGROUPMEMBER`) are real and widely discussed in public forensic material.
- The basic `ZMESSAGETYPE` mapping for the low-numbered/common message types is well supported.
- The `Manifest.db` lookup pattern for hashed iOS backup files is correct.
- `@lid` is a real modern identifier form distinct from phone-number JIDs, and `LID.sqlite` also appears in external references. [1][2][4][12][16]

### Best treated as project-local / fixture-derived

The README becomes much less externally verifiable when it moves from **schema facts** to **behavioral interpretation**:

- exact `Status` subcode meanings and normalized strings,
- exact reply-parsing byte signatures,
- exact reaction blob decoding,
- fixture counts,
- the exact full precedence order for display-name resolution,
- `author` vs `eventActor`,
- file-export naming conventions,
- local regression-test assertions.

Those sections should be treated as **implementation knowledge**, not as publicly validated WhatsApp documentation.

### The two places I would soften most

1. **Extended message-type mapping**  
   Public sources are not consistent enough for the exact `10/11/15` mapping you list. I would either:
   - move those values into a “fixture-observed / version-dependent” section, or
   - explicitly label them as reverse-engineered and not externally stable.

2. **LID acronym expansion**  
   The existence and role of `@lid` is well supported, but the expansion of the acronym itself is **not standardized by an authoritative WhatsApp source** in the material I found. I would avoid presenting any expansion as more than a tentative gloss.

## Suggested README wording changes

### Safer wording for the LID section

> `@lid` is a WhatsApp identifier form seen in modern multi-device contexts. Public external sources consistently describe it as a non-phone identifier used for privacy-preserving identity handling. This project therefore treats `@lid` as distinct from a phone-number JID (`@s.whatsapp.net`). When local client-side mapping data is available (for example in WhatsApp caches/databases such as `LID.sqlite`), the runtime may sometimes resolve a `@lid` identity back to a phone-based identity.

### Safer wording for extended message types

> The low-numbered `ZMESSAGETYPE` values used for common message classes (text, image, video, audio, contact, location, URL, file) are externally corroborated. Higher-value mappings used here for status/system/media-specialized rows are best understood as reverse-engineered and version-dependent observations from the current fixture and runtime, not as stable public WhatsApp documentation.

## Sources consulted

1. **Belkasoft** — *iOS WhatsApp Forensics with Belkasoft X*  
   https://belkasoft.com/ios-whatsapp-forensics-with-belkasoft-x

2. **Group-IB** — *All about WhatsApp forensics analysis*  
   https://www.group-ib.com/blog/whatsapp-forensic-artifacts/

3. **Magnet Forensics** — *Artifact Profile - WhatsApp Messenger*  
   https://www.magnetforensics.com/blog/artifact-profile-whatsapp-messenger/

4. **rayed/whatsapp-iphone-backup** — public GitHub extraction code using `Manifest.db` and the WhatsApp app-group domain  
   https://github.com/rayed/whatsapp-iphone-backup/blob/master/main.go

5. **kacos2000/Queries** — public SQL against `ChatStorage.sqlite`  
   https://github.com/kacos2000/queries/blob/master/WhatsApp_Chatstorage_sqlite.sql

6. **Reverse Engineering Stack Exchange** — discussion of `ZWAMESSAGEINFO.ZRECEIPTINFO` as an opaque blob  
   https://reverseengineering.stackexchange.com/questions/30290/figuring-out-whatsapps-receipt-info-storage-format/30298

7. **marmolejo gist** — public conversion SQL joining `ZWAMESSAGE`, `ZWAMEDIAITEM`, and `ZWAGROUPMEMBER`  
   https://gist.github.com/marmolejo/9f19f7f91ee6e58ec44f

8. **A Practical Hands-on Approach to Database Forensics** — public excerpt describing WhatsApp iOS fields/mappings  
   https://dokumen.pub/a-practical-hands-on-approach-to-database-forensics-9783031161261-9783031161278.html

9. **WhatsApp/stickers iOS README** — official WhatsApp GitHub documentation for sticker packaging / WebP payloads  
   https://github.com/WhatsApp/stickers/blob/main/iOS/README.md

10. **DigitalPerito** — public 2026 reverse-engineering post with differing higher-value type mappings  
   https://digitalperito.es/blog/metadatos-whatsapp-forense-analisis-peritaje-2026/

11. **Stack Overflow** — why WhatsApp Web returns `@lid` IDs  
   https://stackoverflow.com/questions/79808809/why-does-whatsapp-web-indexeddb-return-lid-ids-instead-of-phone-numbers-for-s

12. **giuseppecastaldo/ha-addons issue** — linked device IDs replacing phone-number JIDs in practice  
   https://github.com/giuseppecastaldo/ha-addons/issues/131

13. **go-whatsapp-web-multidevice releases** — explicit `LID (Linked ID)` resolution language in public tooling  
   https://github.com/aldinokemal/go-whatsapp-web-multidevice/releases

14. **Timmy O'Mahony** — iCloud backup contents including `.LID.sqlite.enc.icloud`  
   https://timmyomahony.com/blog/backing-up-whatsapp-media-from-icloud/

15. **iVerify** — public incident write-up listing `LID.sqlite` among WhatsApp artifacts targeted on iOS  
   https://iverify.io/blog/darksword-ios-exploit-kit-explained

16. **Radensa / SANS-style iOS apps forensics PDF** — references `Media/Profile`, `Message/Media`, and `stickers` under the shared WhatsApp AppGroup  
   https://newsletter.radensa.ru/wp-content/uploads/2023/10/SANS_DFPS_iOS-APPS-v1.2_09-22.pdf

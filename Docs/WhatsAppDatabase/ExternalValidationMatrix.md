# External and Web Validation Report for `SwiftWABackupAPI` README  

## Methodology

I validated the README against external sources only, prioritizing public forensic write-ups, reverse-engineering references, official WhatsApp/GitHub material where available, and independent public code/examples. 

Because WhatsApp does not publish an official schema reference for `ChatStorage.sqlite`, some claims can only be checked against third-party reverse-engineering sources. For that reason, the labels below mean:

- **`externally corroborated`**: supported by one or more external sources and not materially contradicted by stronger external evidence.
- **`publicly unsettled`**: public sources do not support a single authoritative conclusion, or the available public evidence points in more than one direction.
- **`implementation-specific`**: the current runtime behavior is clear and documented, but the full rule should not be presented as a publicly established WhatsApp behavior.
- **`WA-Web-validated`**: not externally documented in strong public sources, but validated against the visible behavior of WhatsApp Web.

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
| The API's current handling of `ZMESSAGETYPE = 11` as `GIF` and `ZMESSAGETYPE = 15` as `Sticker` matches visible WhatsApp Web behavior on validated examples. | `WA-Web-validated` | Validated with WhatsApp Web. The checked `11` rows behave like GIF-style media in the UI, and the checked `15` rows behave like sticker messages. |
| `@lid` identifiers are non-phone identifiers that appear in modern multi-device WhatsApp contexts. | `externally corroborated` | External discussions, library docs, and protocol tooling consistently describe `@lid` as a non-phone identifier introduced by newer WhatsApp multi-device / privacy-preserving behavior. [12][17][18] |
| `@s.whatsapp.net` is the phone-based JID form, while `@lid` is a separate/private identifier that may need local mapping. | `externally corroborated` | External issue reports and library docs describe both forms and the need to resolve between them. [12][17] |
| A local cache/database such as `LID.sqlite` may exist and help with LID resolution. | `externally corroborated` | External references show `LID.sqlite` present in WhatsApp-related backups/exfiltration targets, which supports the existence of such a cache/database. [14][15] |
| A single authoritative expansion of **LID** is established externally and should be documented as fact. | `publicly unsettled` | Public sources are still inconsistent. Some public tooling calls it **Linked ID**, while Baileys migration docs now call it **Local Identifier**, and lower-level protocol/tooling sources often use `LID` without expanding it at all. I still do not see an authoritative WhatsApp source standardizing the acronym, so the public docs should avoid expanding it. [13][17][18] |
| Author resolution using `ZISFROMME`, `ZWAGROUPMEMBER`, `ZWACHATSESSION`, `ZWAPROFILEPUSHNAME`, and optional LID mapping is plausible. | `externally corroborated` | The underlying tables/fields used in your reasoning are externally documented. The exact logic is your implementation, but the data sources you rely on are externally real. [1][2][5][8] |
| The visible sender-label behavior seen in WhatsApp Web, including `~` prefix display and the fact that bidi control characters are not surfaced to the user, matches the API's current normalization strategy. | `WA-Web-validated` | Validated with WhatsApp Web. The visible author-label behavior observed there matches the API's current normalization strategy. |
| The API's full exact current author-resolution order is publicly established WhatsApp behavior. | `implementation-specific` | WhatsApp Web validates several visible precedence decisions, but not the entire total order branch-by-branch. The distinguishable cases support this quality-aware strategy: a human-friendly saved/direct-chat label can beat push-name alternatives, and a human-readable push name can beat phone-only fallback labels. But some later runtime branches are UI-indistinguishable in practice, so the complete internal order remains implementation-specific rather than publicly established WhatsApp behavior. |
| In WhatsApp Web group-message rendering, a human-friendly push name can outrank phone-only fallback labels coming from direct-chat/session or group-member records. | `WA-Web-validated` | Validated with WhatsApp Web. The visible group-message labels support preferring a human-readable push name over phone-only fallback labels. |
| The current quality-aware author strategy implemented by the API matches WhatsApp Web on the distinguishable group-message cases that were tested. | `WA-Web-validated` | Validated with WhatsApp Web. The distinguishable group-message cases observed there are consistent with the API's current quality-aware strategy, without implying that every internal branch has a publicly proven total order. |
| When the API resolves a `@lid` identity through `LID.sqlite`, the recovered phone number can match the phone rendered by WhatsApp Web beside the author label. | `WA-Web-validated` | Validated with WhatsApp Web. The phone rendered beside the visible author label can match the phone recovered by the API from `LID.sqlite`. |
| The visible quoted-reply behavior rendered by WhatsApp Web matches the API's current `replyTo` output on validated examples. | `WA-Web-validated` | Validated with WhatsApp Web. Quoted replies visible there are consistent with the API's current `replyTo` behavior on the validated examples. |
| Reactions are stored in `ZWAMESSAGEINFO.ZRECEIPTINFO` as binary blobs. | `externally corroborated` | The existence of `ZRECEIPTINFO` as a blob is externally corroborated; it is publicly recognized as opaque receipt-related metadata. [5][6] |
| The visible reaction emoji and reacting participant identity produced by the current API match WhatsApp Web on validated examples. | `WA-Web-validated` | Validated with WhatsApp Web. The checked reaction examples line up with the API's current visible output for emoji plus the reacting participant's visible label and phone where the web shows one. |
| Media retrieval via iOS `Manifest.db` / `Files(fileID, domain, relativePath)` and then locating the hashed file under `<backup>/<prefix>/<fileID>` is the correct general model. | `externally corroborated` | This is standard iOS backup behavior and is also reflected in public WhatsApp extraction code. [4][14] |
| Looking up WhatsApp media by `domain = 'AppDomainGroup-group.net.whatsapp.WhatsApp.shared'` plus relative path is externally grounded. | `externally corroborated` | Public code that extracts WhatsApp data from iPhone backups uses exactly that approach. [4] |
| Profile photos / avatars in WhatsApp iOS data are found under `Media/Profile/`. | `externally corroborated` | Group-IB explicitly lists `/Media/Profile/` for contact/group thumbnails and avatars, and independent training material repeats the same location. [2][16] |
| Sticker assets are associated with `.webp` files. | `externally corroborated` | Group-IB notes a `/stickers/` directory in the shared container, and official WhatsApp sticker documentation for iOS states that sticker payloads use WebP data. [2][9] |

## Overall assessment

### Strongly supported externally

The README is on firm ground in its **high-level forensic model**:

- `ChatStorage.sqlite` is the central iOS message database.
- The app-group domain/path is correct.
- The main tables (`ZWAMESSAGE`, `ZWACHATSESSION`, `ZWAMEDIAITEM`, `ZWAMESSAGEINFO`, `ZWAGROUPMEMBER`) are real and widely discussed in public forensic material.
- The basic `ZMESSAGETYPE` mapping for the low-numbered/common message types is well supported.
- The `Manifest.db` lookup pattern for hashed iOS backup files is correct.
- `@lid` is a real modern identifier form distinct from phone-number JIDs, and `LID.sqlite` also appears in external references. [1][2][4][12][16]

### Main open questions

The main unresolved areas are now concentrated in two claims:

- whether the acronym `LID` has a single authoritative public expansion
- whether the API's full exact participant-label precedence order can be treated as publicly established WhatsApp behavior

Those are still best treated as reverse-engineered, version-sensitive areas rather than settled public WhatsApp documentation.

### The two places I would soften most

1. **LID acronym expansion**  
   The existence and role of `@lid` is well supported, but the expansion of the acronym itself is still **not standardized by an authoritative WhatsApp source** in the material I found. The strongest public technical gloss I found was **Local Identifier**, but other public sources still say **Linked ID**, and lower-level protocol tooling often leaves the acronym unexplained. I would avoid presenting any expansion as fact in the public docs.

2. **Exact author-resolution order**  
   WhatsApp Web strongly supports the current quality-aware strategy at the visible-behavior level, but not every internal branch can be distinguished from the UI. I would document the exact order as the current runtime implementation while avoiding language that presents the full total order as a publicly established WhatsApp rule.

## Suggested README wording changes

### Safer wording for the LID section

> `@lid` is a WhatsApp identifier form seen in modern multi-device contexts. Public external sources consistently describe it as a non-phone identifier used for privacy-preserving identity handling, but they do not agree on a single authoritative expansion of the acronym. This project therefore treats `LID` as an opaque WhatsApp term and treats `@lid` as distinct from a phone-number JID (`@s.whatsapp.net`). When local client-side mapping data is available (for example in WhatsApp caches/databases such as `LID.sqlite`), the runtime may sometimes resolve a `@lid` identity back to a phone-based identity.

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

17. **Baileys migration docs** — explicit `LID (Local Identifier)` terminology in public WhatsApp tooling docs  
   https://baileys.wiki/docs/migration/to-v7.0.0/

18. **whatsmeow `jid.go`** — public protocol/tooling source using `lid` as a first-class JID domain without expanding the acronym  
   https://github.com/tulir/whatsmeow/blob/main/types/jid.go

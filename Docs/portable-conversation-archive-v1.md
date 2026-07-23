# Portable conversation archive v1

## Status

Implemented in SwiftWABackupAPI 5.0.0 on 23 July 2026.

The implementation provides the portable data model, safe ZIP codec, validated
directory handle, composition-source adapter, progress/cancellation, and
synthetic contract and hostile-input tests. It does not install an imported
source in any application's library.

## Purpose and composition boundary

A `.fmcchat` file transports one conversation snapshot and its referenced
media. It is another representation of `ConversationSource`, not a separate
merge engine:

```text
local export ───────► ConversationSource ─┐
                                          ├─► ConversationCompositionEngine
.fmcchat ─► validated directory ─► source ┘
```

The archive represents the source's relative perspective. `sourceUser` means
the user whose export produced the document. The package does not store that
user's identity. During composition, the engine infers the relationship between
source perspectives from content evidence, or the client supplies an optional
operation-scoped `ConversationPerspectiveHint`.

## Canonical layout

The ZIP has no wrapping directory and permits only regular-file entries:

```text
manifest.json
chat.json
Media/<content-hash>-<original-safe-name>
```

`Media` is represented by its files; no directory entry is stored. Empty media
is valid.

`manifest.json` declares:

- schema and format identifiers;
- package creation and producer metadata;
- codec implementation and algorithm versions;
- the conversation descriptor;
- message count and date range;
- `chat.json` size and SHA-256;
- sorted media path, size, and SHA-256 declarations;
- a digest over the canonical content declaration.

`chat.json` contains:

- a matching conversation descriptor;
- stable `ArchiveMessageID` values encoded as UUID strings;
- portable messages in canonical date/ID order;
- replies expressed with stable message IDs;
- source-relative authors and reactions;
- media references using canonical archive paths;
- contacts expressed with canonical participant addresses.

Dates use UTC RFC 3339 with fractional seconds. JSON keys are sorted. Stable
message IDs supplied by the client are preserved; missing IDs are generated
deterministically from message content and occurrence.

## Owner-identity rule

`PortableMessageAuthor(role: .sourceUser)` must have:

- `identityHint == nil`;
- `displayName == nil` in archives created by the codec.

The validator rejects a source-user identity in messages or reactions. Other
participants may use canonical phone, phone-JID, or LID-JID addresses. Display
names are never used as identity.

For individual chats, the descriptor identifies the counterpart, not the source
user. For groups, it contains the normalized full `@g.us` JID. No global owner
record is introduced. Contact cards and profile photos are retained only for
participants proven not to be the source user: the individual counterpart, or
resolved incoming message/reaction authors in a group. Unproven contacts are
omitted rather than risking disclosure of the owner.

## Public API

```swift
public struct PortableConversationArchiveCodec {
    public init(limits: PortableArchiveLimits = .default)

    public func createArchive(
        from source: ConversationSource,
        producer: PortableArchiveProducer,
        destinationURL: URL,
        overwriteExisting: Bool = false,
        progress: WABackupProgressHandler? = nil,
        cancellation: WABackupCancellationHandler? = nil
    ) throws -> PortableConversationArchiveInfo

    public func inspectArchive(
        at archiveURL: URL,
        progress: WABackupProgressHandler? = nil,
        cancellation: WABackupCancellationHandler? = nil
    ) throws -> PortableConversationArchiveInfo

    public func extractValidatedArchive(
        at archiveURL: URL,
        to destinationDirectory: URL,
        progress: WABackupProgressHandler? = nil,
        cancellation: WABackupCancellationHandler? = nil
    ) throws -> PortableConversationDirectory

    public func openValidatedDirectory(
        at directoryURL: URL
    ) throws -> PortableConversationDirectory
}
```

`PortableConversationDirectory` has no public arbitrary-directory initializer.
Only the codec can produce it after validation. Its adapter is:

```swift
public func makeConversationSource(
    id: ConversationSourceID,
    perspectiveHint: ConversationPerspectiveHint? = nil
) throws -> ConversationSource
```

The resulting source has `.portableDocument` kind and can be mixed with any
number of local or portable sources in `analyze`, `materialize`, or `compose`.

## Creation guarantees

Creation:

1. validates the source and producer;
2. rejects duplicate source message IDs and unsafe or missing media;
3. converts authors to relative roles and removes source-user identity;
4. hashes source media in streaming chunks;
5. deduplicates equal media by size plus full SHA-256;
6. writes a canonical temporary directory;
7. validates that directory through the import validator;
8. writes a temporary ZIP using ZIPFoundation;
9. fully inspects the finished ZIP;
10. installs it at the destination only after all checks pass.

An existing destination is rejected unless `overwriteExisting` is true. When
replacement is requested, the previous file is moved aside and restored if the
final installation fails. Cancellation or validation failure leaves no partial
archive.

## Inspection and extraction guarantees

Inspection validates the central directory before extracting any path. It then
streams and hashes media entries, decodes the two bounded JSON entries, and
checks the complete declaration/content relationship.

The codec rejects:

- absolute paths, `.` or `..`, empty components, hidden components, NUL,
  backslash, colon, and noncanonical Unicode paths;
- unexpected root files, nested media directories, directory entries,
  symlinks, and case-insensitive duplicate paths;
- entry count, path length, individual size, total expanded size, JSON size,
  archive size, compression ratio, and integer-overflow violations;
- missing, extra, undeclared, or unreferenced files;
- size, SHA-256, content-digest, schema, format, descriptor, count, date, stable
  ID, reply, author, duration, coordinate, and media-reference inconsistencies.

Extraction runs inspection first, rechecks the archive hash, writes only the
validated entry set to an absent or empty destination, and opens the resulting
directory with the independent directory validator. Failure removes only files
created by that operation.

Default limits are configurable through `PortableArchiveLimits`:

| Limit | Default |
| --- | ---: |
| ZIP size | 100 GB |
| Total expanded size | 250 GB |
| One entry | 50 GB |
| One JSON document | 2 GB |
| Entry count | 200,000 |
| Compression ratio | 200:1 |
| UTF-8 path length | 512 bytes |

The codec uses ZIPFoundation 0.9.20 and does not launch `zip`, `unzip`, or
`ditto`. SHA-256 uses CryptoKit on supported Apple systems, including Ventura,
with the package's deployment-target-preserving Swift implementation as a
fallback.

## Progress and cancellation

The codec emits:

- `creatingPortableConversationArchive`;
- `inspectingPortableConversationArchive`;
- `extractingPortableConversationArchive`;
- `completed`.

Units use `mediaFiles`, `archiveEntries`, or `phases`. Cancellation is checked
while hashing, building, reading, writing, inspecting, and extracting.

## Client responsibilities

SwiftWABackupAPI writes:

- the requested `.fmcchat` destination;
- an explicitly requested extraction/staging directory;
- a composition staging directory when materialization is requested separately.

The client remains responsible for:

- file-picker and confirmation UI;
- choosing persistent `Imports` and derived-view locations;
- registering an imported contribution in its own manifest;
- atomic installation and rollback of its library state;
- rebuilding a view after an import is removed;
- storing any operation evidence or user-supplied perspective hint.

The codec has no knowledge of `library.json`, `Exports`, `Imports`, or
`MergedChats`.

## Test coverage

Synthetic tests currently cover:

- group round trip with stable IDs, replies, reactions, and recomposition;
- individual round trip and absence of serialized source-user identity;
- exclusion of the owner's contact card and profile photo;
- content-based media deduplication;
- deterministic ordering for equal timestamps;
- traversal and unexpected ZIP paths;
- tampered JSON and undeclared directory files;
- size limits, cooperative cancellation, and partial-output cleanup;
- failed overwrite preserving previous bytes;
- duplicate source message IDs;
- the Free My Chats boundary from creation through extraction and
  cross-perspective materialization.

The complete composition suite remains the regression oracle for local unified
views and conservative cross-perspective behavior.

## Deliberate v1 limits

- no package signature or sender authentication;
- no encryption;
- no native WhatsApp TXT/ZIP import;
- no multipart or multidisk archives;
- no fuzzy edit reconciliation;
- no persistent import record or application UI;
- no stored global owner identity.

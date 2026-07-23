# Current unified-view conversation composition

`ConversationCompositionPolicy.currentUnifiedView` combines one or more
`ExportedChatDocument` version 1 sources that represent the same conversation
from the same source-relative user.

It is intentionally narrower than cross-person chat import. The caller must
provide one `ConversationPerspectiveConstraint.samePerspective` that covers
every source. This constraint means that `isFromMe` has the same meaning across
the inputs; it does not identify or persist an owner.

## Operation split

`analyze` is read-only. It validates inputs, hashes media, builds exact logical
message groups, and returns an opaque `PreparedConversationComposition` plus a
serializable `ConversationCompositionPlan`.

`materialize` revalidates the inputs and writes a complete candidate into a
destination that does not exist or is empty:

```text
destination/
├── chat.json
└── Media/
```

The engine never writes application manifests and does not know paths such as
`Exports`, `MergedChats`, or `library.json`. The client owns installation,
replacement, rollback, and deletion.

## Conversation identity

All sources must have the same chat type.

- Groups match by normalized full `@g.us` JID.
- Individual chats match when their canonical counterpart identities share an
  exact address or an explicitly supplied alias.
- A phone JID and LID do not match merely because they look related. Supply a
  `conversationIdentityHint` containing both addresses when that relationship
  has already been resolved.
- Display names and photos never establish identity.

## Exact message key

The initial algorithm uses these fields:

- timestamp rounded to milliseconds;
- source-relative author role;
- message type;
- text;
- caption;
- media SHA-256 and byte count;
- duration;
- latitude and longitude.

It excludes source integer IDs, `chatId`, replies, previews, reactions, warning
text, display names, and export dates.

Text and captions use Unicode NFC and convert CRLF or CR line endings to LF.
Whitespace, case, punctuation, duration, coordinates, and timestamps are not
relaxed. There is no time tolerance or contextual alignment in this profile.

An occurrence is one `MessageInfo` in one source document. Occurrences with the
same exact key form one logical message. Two identical occurrences within one
source are also collapsed for parity with the existing unified-view behavior;
the plan reports `duplicateFingerprintWithinSource`.

## Author semantics

- `isFromMe == true` becomes the relative role `sourceUser`.
- An incoming resolved participant uses a canonical phone, phone JID, or LID.
- An incoming individual message without an author uses the conversation
  counterpart.
- Other missing authors remain unresolved.

Contradictory combinations of `isFromMe` and `MessageAuthor.kind` are invalid.

## Ordering and representative selection

All occurrences are ordered by:

1. message date;
2. source position in the input array;
3. original message position in that source.

The first occurrence of a logical group is its representative. Its content,
reactions, warning, visible author, and reply metadata win. The target source is
used for chat name, contact JID, archived state, and chat avatar. Contacts prefer
the target source, then the most recent source date, then input order.

The target source is explicit. Clients should normally choose the newest local
export when they want the latest presentation metadata.

## IDs and replies

Materialized integer IDs are consecutive `1...n`. Replies are translated through
the source occurrence, logical-message, and materialized-ID mappings. If a reply
target is absent, `replyTo` becomes nil and its preview is preserved.

`ArchiveMessageID` values are independent of WhatsApp database primary keys. A
target-provided stable ID wins, followed by another source-provided ID. Without
one, the current algorithm derives a deterministic UUID from the exact logical
message digest. Reusing one stable ID for different logical messages is an error.

## Media

Referenced source media must be a safe single filename and a regular non-symlink
file below the source `Media` directory. SHA-256 is calculated by streaming.

The materialized name starts with 12 hexadecimal SHA-256 characters and the
safe representative filename. The prefix grows if needed to avoid a collision.
Identical bytes with different source names are written once; different bytes
with the same source name remain separate. Output files are physical copies, not
hard links.

`ChatInfo.mediaByteCount` counts unique message media only. Chat avatars and
contact photos are copied when selected but are not included in that value.

## Statistics and removal impact

`inputMessageCount` counts occurrences. `materializedMessageCount` counts exact
logical groups. `ConversationSourceImpact` distinguishes logical messages shared
with another source from those exclusive to one source.

`ConversationCompositionPlan.removalImpact(of:)` reports how many logical
messages and unique media bytes would disappear if the client rebuilt without a
source. It does not write or remove anything.

## Consistency, cancellation, and privacy

Media hashes and file signatures captured by `analyze` are checked again before
materialization and while copying. A changed input raises `inputChanged`.

Cancellation is cooperative during validation, hashing, message traversal, and
copying. A failed operation removes only output created by that call. Progress
events never contain chat text, names, phone numbers, or JIDs in `currentItem`.

## Deliberate limits

This profile does not implement:

- sources from different people or perspectives;
- perspective inference;
- timestamp tolerance;
- contextual sequence alignment;
- conflict classification;
- portable `.fmcchat` archives;
- ZIP processing;
- application-library installation.

Those capabilities can extend the same source, plan, and materialization API;
they must not silently weaken `currentUnifiedView`.


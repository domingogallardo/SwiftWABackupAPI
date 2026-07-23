# Cross-perspective conversation materialization

## Implementation status

The current API implements conservative diagnosis, target-relative N-ary
materialization, stable IDs, replies, reactions, media, systematic offsets,
staging cleanup, progress, cancellation, synthetic coverage, and the portable
`.fmcchat` v1 codec. Application-library persistence and installation remain a
separate client layer.

`ConversationCompositionPolicy.conservativeDefault` supports the same
`analyze` → `materialize` split as `currentUnifiedView`. It first runs the
read-only cross-perspective diagnostic. Only an `applicable` diagnosis produces
a `PreparedConversationComposition`; `rejected` and `requiresReview` results are
thrown with their complete diagnostic and no destination is created.

## Target-relative authors

The output is oriented to `targetSourceID`, never to a stored owner identity.

- target messages retain their `isFromMe` meaning;
- a same-perspective source retains its relative author roles;
- an opposite individual source is binary: source-user becomes the target
  counterpart and source counterpart becomes the target user;
- an opposite group source uses evidence-backed participant keys collected from
  aligned messages or optional operation hints;
- an exclusive group message whose author cannot be oriented rejects the plan;
- transformed `MessageAuthor.kind` and reaction authors agree with the target
  `isFromMe` meaning.

Hints and `sourceIdentity` constraints are arguments to one operation. They are
not written as a library-wide owner identity.

## Logical messages

Strong ordered anchors are always grouped. A stable message ID groups compatible
content and rejects incompatible content. Additional equal target-oriented
content is grouped only when it occurs at most once per source and falls within
the timestamp tolerance; repetitive ambiguous sequences are kept separate.

The target occurrence is the representative when present. Otherwise the newest
source snapshot wins, with stable source and message ordering as tie breakers.
Systematic timestamp offsets are applied to source-exclusive messages only when
the policy explicitly enables them.

Materialized messages are sorted chronologically and receive consecutive integer
IDs. Replies are translated through the logical group map. Stable archive IDs
remain independent of source and materialized integer IDs.

## Metadata and files

The target supplies chat name, contact JID, archived state, and avatar. Counts,
last-message date, and media bytes are recalculated. Contacts prefer the target
snapshot. Media validation, hashing, deterministic naming, content deduplication,
copying, cancellation, input revalidation, and staging cleanup reuse the current
unified-view implementation.

The engine writes only:

```text
destination/
├── chat.json
└── Media/
```

The client owns library manifests, installation, replacement, rollback, and
deletion.

## Deliberate limits

- no automatic application-library installation;
- no fuzzy edit reconciliation;
- no contextual disambiguation of repeated weak messages;
- no materialization of a diagnostic that requires manual review;
- no persistent owner identity.

Portable packages are documented in
[Portable conversation archive v1](portable-conversation-archive-v1.md). A
validated package becomes another `ConversationSource`; it does not introduce a
second composition algorithm.

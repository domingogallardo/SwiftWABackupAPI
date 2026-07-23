# Cross-perspective conversation diagnostics

## Implementation status

The read-only diagnostic, the materialization layer that consumes an applicable
result, and the portable `.fmcchat` v1 codec are implemented. Persistent
application-library installation remains a client concern.

`ConversationCompositionEngine.diagnose` is the read-only Phase 0 of
cross-person conversation composition. It reuses `ConversationSource`, media
validation, content hashing, progress, cancellation, and policy types from the
current unified-view engine.

This entry point remains read-only. An applicable result can now be consumed by
the conservative profile's `analyze`, `materialize`, or `compose` operations;
those operations are documented separately. Package creation and extraction are
separate `PortableConversationArchiveCodec` operations and never alter an input
source.

## Perspective semantics

`isFromMe` identifies the user represented by one source. It is never converted
to a global stored owner. For a matched message:

- `sourceUser` against `sourceUser` supports the same perspective;
- `sourceUser` against a resolved participant supports opposite perspectives;
- participant against participant does not decide the source-user relationship;
- contradictory evidence produces `conflicting`.

An optional `ConversationPerspectiveHint` or
`ConversationPerspectiveConstraint` can resolve an otherwise incomplete
relationship. Strong contradictory content evidence still wins by making the
result conflicting. Hints never replace the overlap requirement.

## Conservative alignment

The initial diagnostic uses message type, normalized text/caption, media
SHA-256 and byte count, duration, and location as its central signature. It does
not include source IDs, `chatId`, display names, or relative author.

Only unique strong signatures become candidates. Candidates must be within the
policy timestamp tolerance and form an increasing sequence in both sources.
This gives normal complexity of `O(totalMessages log totalMessages +
totalMediaBytes)` without a full quadratic LCS.

Short repetitive values such as `OK`, `Sí`, and single emoji are deliberately
not strong anchors in this phase. Context-window matching is a later calibration
step.

Groups additionally require the same normalized full `@g.us` JID. Individual
chats can be recognized across opposite perspectives from strong ordered
content and an inferred perspective relationship. Equal display names are
ignored.

## Result and safety

`ConversationCompositionDiagnostic` contains:

- source digests;
- conversation equivalence;
- per-source perspective resolution;
- anchor, coverage, order, and timestamp statistics;
- unresolved-author and unorientable-exclusive counts;
- confidence, disposition, and stable reason codes.

Semantic rejection is data: `different`, `ambiguous`, insufficient overlap, or
unresolved orientation returns a diagnostic with `rejected` or
`requiresReview`. Invalid files, unsafe media, cancellation, and I/O failures
remain thrown errors.

`privacySafeReport` removes participant identities and the normalized group JID
while retaining hashes and measurements. The CLI always serializes this form.
Neither the engine nor the command writes into input directories.

## Current deliberate limits

- no contextual windows for weak/repetitive messages;
- no conflict samples with private content;
- no persistent owner identity;
- no application-library installation.

See [Cross-perspective materialization](conversation-composition-cross-perspective.md)
for the write-side contract and its additional conservative limits.

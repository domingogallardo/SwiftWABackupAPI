# App Migration Guide: `MessageInfo.author`

This document is intended for the agent or developer updating an app that consumes `SwiftWABackupAPI`.

## Summary

`MessageInfo.senderName` and `MessageInfo.senderPhone` have been removed from the public API.

Use `MessageInfo.author` instead.

## Old To New Mapping

| Old field | New field |
| --- | --- |
| `message.senderName` | `message.author?.displayName` |
| `message.senderPhone` | `message.author?.phone` |
| outgoing message detection with missing sender fields | `message.author?.kind == .me` |

## Recommended Rendering Rules

For most UI code, use this order:

1. If `message.author?.kind == .me`, render the message as sent by the owner.
2. Else use `message.author?.displayName` if present.
3. Else use `message.author?.phone` if present.
4. Else fall back to a generic label such as `"Unknown sender"`.

## Important Behavioral Notes

- Outgoing messages now expose an explicit author object:
  - `author.kind = .me`
  - `author.displayName = "Me"`
  - `author.source = .owner`
- Incoming individual messages resolve from the chat session:
  - `author.kind = .participant`
  - `author.phone = chat.contactJid.extractedPhone`
  - `author.jid = chat.contactJid`
  - `author.source = .chatSession`
- Incoming group messages may resolve from different sources:
  - `.chatSession`
  - `.pushName`
  - `.groupMember`
  - `.messageJid`

`author.source` is useful when the app wants to explain where a display name came from or debug unexpected sender labels.

## Search And Replace Checklist

Search the app codebase for:

- `.senderName`
- `.senderPhone`

Then replace usages with:

```swift
message.author?.displayName
message.author?.phone
```

If the app used the old `nil senderName/nil senderPhone` pattern to detect owner messages, replace that with:

```swift
message.author?.kind == .me
```

## Example

Old:

```swift
let label = message.senderName ?? message.senderPhone ?? "Me"
```

New:

```swift
let label: String

if message.author?.kind == .me {
    label = "Me"
} else {
    label = message.author?.displayName
        ?? message.author?.phone
        ?? "Unknown sender"
}
```

## JSON Consumers

If the app reads encoded JSON instead of Swift models:

- remove support for `senderName`
- remove support for `senderPhone`
- read the `author` object instead

See [JSONContract.md](./JSONContract.md) for the exact payload shape.

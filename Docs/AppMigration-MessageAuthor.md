# App Migration Guide: Message Identity

This document is intended for the agent or developer updating an app that consumes `SwiftWABackupAPI`.

## Summary

`MessageInfo.senderName` and `MessageInfo.senderPhone` have been removed from the public API.

Use the structured identity fields instead:

- `MessageInfo.author` for real user-authored chat messages
- `MessageInfo.eventActor` for status/system rows that refer to a participant but do not represent a normal authored message

## Old To New Mapping

| Old field | New field |
| --- | --- |
| `message.senderName` on a normal chat message | `message.author?.displayName` |
| `message.senderPhone` on a normal chat message | `message.author?.phone` |
| sender label on a system/status row | `message.eventActor?.displayName ?? message.eventActor?.phone` |
| outgoing message detection with missing sender fields | `message.author?.kind == .me` |

## Recommended Rendering Rules

For most UI code, use this order:

1. If `message.author?.kind == .me`, render the message as sent by the owner.
2. Else if `message.author` exists, use `message.author?.displayName` and then `message.author?.phone`.
3. Else if `message.eventActor` exists, render the row as an event associated with that participant.
4. Else fall back to a generic label such as `"System event"` or `"Unknown sender"`, depending on the UI.

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
  - `.addressBook`
  - `.lidAccount`
  - `.pushName`
  - `.pushNamePhoneJid`
  - `.groupMember`
  - `.messageJid`
- When `author.source` is `.pushName` or `.pushNamePhoneJid`, `author.displayName`
  is intentionally rendered as `~ Name` to match WhatsApp Web's sender label style
  inside group conversations.
- In group chats, a `.chatSession` label that is only a formatted phone number is now
  treated as weaker than a human-readable push name. This matches WhatsApp Web cases
  where the visible sender label is a `~ Name` push-name label rather than a
  formatted phone number.
- When `author.source` is `.lidAccount`, `author.displayName` may still use that
  same `~ Name` style, but the phone and JID were recovered from WhatsApp's
  `LID.sqlite` account cache instead of being inferred from the visible `@lid`.
- `author.phone` is now intentionally conservative:
  - for `.addressBook`, `.chatSession`, `.lidAccount`, and `.pushNamePhoneJid`, it usually contains a real phone number
  - for ambiguous `@lid` identities resolved only through `.pushName`, it may be `nil`
  - the API no longer treats raw LID digits as if they were a phone number
- Status/system rows may leave `author == nil` and populate `eventActor` instead.
- Some status rows have neither a real author nor a meaningful participant phone, because WhatsApp stores them as chat-level events rather than authored messages.

`author.source` and `eventActor.source` are useful when the app wants to explain where a display name came from or debug unexpected sender labels.

## Search And Replace Checklist

Search the app codebase for:

- `.senderName`
- `.senderPhone`

Then replace usages with:

```swift
message.author?.displayName
message.author?.phone
```

For status/system rows, also consider:

```swift
message.eventActor?.displayName
message.eventActor?.phone
```

If the app used the old `nil senderName/nil senderPhone` pattern to detect owner messages, replace that with:

```swift
message.author?.kind == .me
```

## Example: Message Bubble Label

Old:

```swift
let label = message.senderName ?? message.senderPhone ?? "Me"
```

New:

```swift
let label: String

if message.author?.kind == .me {
    label = "Me"
} else if let author = message.author {
    label = author.displayName
        ?? author.phone
        ?? "Unknown sender"
} else if let actor = message.eventActor {
    label = actor.displayName
        ?? actor.phone
        ?? "System event"
} else {
    label = "System event"
}
```

## Example: Status/Event Copy

When the row is a status or group event, treat `eventActor` as the participant associated with the event, not as a conventional message author:

```swift
if message.messageType == "Status", let actor = message.eventActor {
    let name = actor.displayName ?? actor.phone ?? "Someone"
    print("Event associated with \(name)")
}
```

## JSON Consumers

If the app reads encoded JSON instead of Swift models:

- remove support for `senderName`
- remove support for `senderPhone`
- read `author` for real authored messages
- read `eventActor` for status/system rows

See [JSONContract.md](./JSONContract.md) for the exact payload shape.

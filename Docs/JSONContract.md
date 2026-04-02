# JSON Contract

This document defines the canonical JSON shape exposed by `SwiftWABackupAPI` when encoding the public `Encodable` models with:

- `JSONEncoder.dateEncodingStrategy = .iso8601`
- `JSONEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]`

The contract is verified by the local private regression suite that accompanies the project.

## Encoding Rules

- Dates are encoded as ISO 8601 strings with timezone information, for example `2024-04-03T11:24:16Z`.
- Object keys are sorted when using the recommended encoder configuration above.
- Optional properties are omitted when their value is `nil`.
- Arrays preserve the order returned by the API.

## `Reaction`

```json
{
  "emoji": "👍",
  "author": {
    "displayName": "Sample Contact",
    "jid": "15550000001@s.whatsapp.net",
    "kind": "participant",
    "phone": "15550000001",
    "source": "chatSession"
  }
}
```

| Field | Type | Required | Description |
| --- | --- | --- | --- |
| `emoji` | `String` | Yes | Emoji used in the reaction. |
| `author` | `MessageAuthor` | Yes | Structured identity of the participant who reacted. |

## `ChatInfo`

```json
{
  "chatType": "individual",
  "contactJid": "15550000001@s.whatsapp.net",
  "id": 44,
  "isArchived": false,
  "lastMessageDate": "2024-04-03T11:24:16Z",
  "name": "Sample Contact",
  "numberMessages": 153,
  "photoFilename": "chat_44.jpg"
}
```

| Field | Type | Required | Description |
| --- | --- | --- | --- |
| `id` | `Int` | Yes | Chat identifier from `ZWACHATSESSION.Z_PK`. |
| `contactJid` | `String` | Yes | Raw WhatsApp JID for the chat. |
| `name` | `String` | Yes | Resolved chat display name. |
| `numberMessages` | `Int` | Yes | Number of supported messages returned by the API. |
| `lastMessageDate` | `String` | Yes | ISO 8601 timestamp for the latest supported message. |
| `chatType` | `"group" | "individual"` | Yes | Chat type exposed by the API. |
| `isArchived` | `Bool` | Yes | Whether the chat is archived. |
| `photoFilename` | `String` | No | Copied avatar filename when photo export is requested and available. |

## `MessageInfo`

```json
{
  "author": {
    "displayName": "Sample Contact",
    "jid": "15550000001@s.whatsapp.net",
    "kind": "participant",
    "phone": "15550000001",
    "source": "chatSession"
  },
  "caption": "Example caption",
  "chatId": 44,
  "date": "2024-04-03T11:24:16Z",
  "id": 125482,
  "isFromMe": false,
  "latitude": 38.3456,
  "longitude": -0.4815,
  "mediaFilename": "example.jpg",
  "message": "Example message",
  "messageType": "Text",
  "reactions": [
    {
      "emoji": "👍",
      "author": {
        "displayName": "Me",
        "kind": "me",
        "source": "owner"
      }
    }
  ],
  "replyTo": 125479,
  "seconds": 12
}
```

| Field | Type | Required | Description |
| --- | --- | --- | --- |
| `id` | `Int` | Yes | Message identifier from `ZWAMESSAGE.Z_PK`. |
| `chatId` | `Int` | Yes | Parent chat identifier. |
| `message` | `String` | No | Message text or normalized event text. |
| `date` | `String` | Yes | ISO 8601 timestamp for the message. |
| `isFromMe` | `Bool` | Yes | Whether the message was sent by the owner. |
| `messageType` | `String` | Yes | Human-readable message type name. |
| `author` | `MessageAuthor` | No | Structured identity for a real user-authored message. |
| `eventActor` | `MessageAuthor` | No | Participant associated with a status/system row when there is no real authored message. |
| `caption` | `String` | No | Media caption or title. |
| `replyTo` | `Int` | No | Identifier of the replied-to message when it can be resolved. |
| `mediaFilename` | `String` | No | Exported media filename when media is copied or resolved. |
| `reactions` | `[Reaction]` | No | Reactions attached to the message. |
| `error` | `String` | No | Optional warning associated with media handling. |
| `seconds` | `Int` | No | Duration for audio and video messages. |
| `latitude` | `Double` | No | Latitude for location messages. |
| `longitude` | `Double` | No | Longitude for location messages. |

## `MessageAuthor`

```json
{
  "displayName": "Sample Contact",
  "jid": "15550000001@s.whatsapp.net",
  "kind": "participant",
  "phone": "15550000001",
  "source": "chatSession"
}
```

| Field | Type | Required | Description |
| --- | --- | --- | --- |
| `kind` | `"me" | "participant"` | Yes | Whether the author is the owner or another participant. |
| `displayName` | `String` | No | Best-effort display name selected by the API. Names derived from WhatsApp profile push names are prefixed with `~` to match WhatsApp Web's group-message rendering. In groups, a phone-only direct-chat label is treated as fallback and does not outrank a human-readable push name. |
| `phone` | `String` | No | Real phone number when the API can resolve one confidently. Ambiguous `@lid` identities intentionally leave this field unset instead of exposing the raw LID digits as if they were a phone number. |
| `jid` | `String` | No | Raw WhatsApp JID when it can be determined. |
| `source` | `"owner" | "chatSession" | "addressBook" | "lidAccount" | "pushName" | "pushNamePhoneJid" | "groupMember" | "messageJid"` | Yes | Data source used by the API to resolve the identity. |

## `MessageInfo` Example For Status/System Rows

```json
{
  "chatId": 44,
  "date": "2024-04-03T11:24:16Z",
  "eventActor": {
    "displayName": "Sample Contact",
    "jid": "15550000001@s.whatsapp.net",
    "kind": "participant",
    "phone": "15550000001",
    "source": "chatSession"
  },
  "id": 125600,
  "isFromMe": false,
  "message": "Event payload from WhatsApp",
  "messageType": "Status"
}
```

## `ContactInfo`

```json
{
  "name": "Sample Contact",
  "phone": "15550000001",
  "photoFilename": "sample_contact.jpg"
}
```

| Field | Type | Required | Description |
| --- | --- | --- | --- |
| `name` | `String` | Yes | Resolved display name. |
| `phone` | `String` | Yes | Phone number derived from the contact JID. |
| `photoFilename` | `String` | No | Copied avatar filename when available. |

## `ChatDumpPayload`

```json
{
  "chatInfo": { "...": "..." },
  "contacts": [
    { "...": "..." }
  ],
  "messages": [
    { "...": "..." }
  ]
}
```

| Field | Type | Required | Description |
| --- | --- | --- | --- |
| `chatInfo` | `ChatInfo` | Yes | Chat metadata for the export. |
| `messages` | `[MessageInfo]` | Yes | Messages returned for the chat. |
| `contacts` | `[ContactInfo]` | Yes | Contacts resolved for the chat. |

## Notes

- `ChatDump` remains available as the legacy tuple returned by `getChat(...)`.
- `ChatDumpPayload` is the recommended type for JSON export because it is stable, explicit, and directly `Encodable`.
- `MessageInfo.author` is reserved for real authored messages.
- `MessageInfo.eventActor` is used for status/system rows that refer to a participant but are not authored chat messages in the usual sense.
- Consumers should not assume that every message has a phone-bearing real author.
- `MessageAuthor.source = "lidAccount"` means the visible sender label still comes from WhatsApp identity data such as push names, while the real phone number was recovered from WhatsApp's `LID.sqlite` account cache.
- `MessageAuthor.source = "chatSession"` does not mean that `ZWACHATSESSION.ZPARTNERNAME` always won the display-name decision. In group chats, the runtime may ignore a phone-only chat-session label and prefer a `pushName` instead.
- `senderName` and `senderPhone` are no longer part of the public `MessageInfo` contract.

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
  "senderPhone": "15550000001"
}
```

| Field | Type | Required | Description |
| --- | --- | --- | --- |
| `emoji` | `String` | Yes | Emoji used in the reaction. |
| `senderPhone` | `String` | Yes | Phone number derived from the reacting JID, or `"Me"` for the owner. |

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
      "senderPhone": "Me"
    }
  ],
  "replyTo": 125479,
  "seconds": 12,
  "senderName": "Sample Contact",
  "senderPhone": "15550000001"
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
| `senderName` | `String` | No | Resolved display name for incoming messages. |
| `senderPhone` | `String` | No | Resolved phone number for incoming messages. |
| `caption` | `String` | No | Media caption or title. |
| `replyTo` | `Int` | No | Identifier of the replied-to message when it can be resolved. |
| `mediaFilename` | `String` | No | Exported media filename when media is copied or resolved. |
| `reactions` | `[Reaction]` | No | Reactions attached to the message. |
| `error` | `String` | No | Optional warning associated with media handling. |
| `seconds` | `Int` | No | Duration for audio and video messages. |
| `latitude` | `Double` | No | Latitude for location messages. |
| `longitude` | `Double` | No | Longitude for location messages. |

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

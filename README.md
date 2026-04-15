# SwiftWABackupAPI

`SwiftWABackupAPI` is a Swift package for exploring WhatsApp data stored inside iPhone backups that contain WhatsApp data. It includes backup-discovery diagnostics for encrypted backups, while the chat and export APIs still operate on backups that are confirmed to be non-encrypted. It powers the companion macOS CLI application [WABackupExtractor](https://github.com/domingogallardo/WABackupExtractor), but it can also be consumed directly from your own Swift tools and apps.

A full Python port of this library is also available as [PyWABackupAPI](https://github.com/domingogallardo/PyWABackupAPI).

## Privacy Warning

This package is intended for legitimate backup, recovery, export, and personal analysis workflows.

Accessing or processing WhatsApp conversations without the explicit consent of the people involved can violate privacy laws, workplace policies, and WhatsApp terms of service. Make sure you have the legal and ethical right to inspect the data before using this package.

## What The Package Exposes

The public API is centered on `WABackup`:

- Discover available iPhone backups with `getBackups()`
- Inspect backups with encryption diagnostics via `inspectBackups()`
- Connect to a WhatsApp `ChatStorage.sqlite` database with `connectChatStorageDb(from:)`
- List chats with `getChats(directoryToSavePhotos:)`
- Export a chat with `getChat(chatId:directoryToSaveMedia:)`

Returned models are `Encodable` and designed to be easy to serialize:

- `BackupDiscoveryInfo`
- `BackupDiscoveryStatus`
- `ChatInfo`
- `MessageInfo`
- `MessageAuthor`
- `ContactInfo`
- `Reaction`
- `ChatDumpPayload`

## Requirements

- A macOS environment with access to an iPhone backup directory
- Permission to read the backup folder
- A backup that contains WhatsApp data

For chat listing and export, the selected backup must be non-encrypted. Use
`inspectBackups()` if you need an explicit readiness check before calling
`connectChatStorageDb(from:)`.

By default, `WABackup` looks under:

```text
~/Library/Application Support/MobileSync/Backup/
```

On many systems you will need to grant Full Disk Access to the host app or terminal.

## Installation

Add the package dependency in `Package.swift` using the release rule that matches how you publish or consume the package:

```swift
.package(url: "https://github.com/domingogallardo/SwiftWABackupAPI.git", from: "2.1.0")
```

Version `2.0.0` introduced a breaking API change:

- `getChat(chatId:directoryToSaveMedia:)` now returns `ChatDumpPayload`
- `getChatPayload(chatId:directoryToSaveMedia:)` was removed

Then add the product to your target dependencies:

```swift
.product(name: "SwiftWABackupAPI", package: "SwiftWABackupAPI")
```

## Basic Usage

Recommended discovery flow:

```swift
import Foundation
import SwiftWABackupAPI

let backupAPI = WABackup()
let inspections = try backupAPI.inspectBackups()
guard let backup = inspections.first(where: { $0.status == .ready })?.backup else {
    throw NSError(domain: "Example", code: 1)
}

try backupAPI.connectChatStorageDb(from: backup)

let chats = try backupAPI.getChats()
let payload = try backupAPI.getChat(chatId: chats[0].id, directoryToSaveMedia: nil)
print(payload.chatInfo.name)
print(payload.messages.count)
```

Compatibility flow retained for existing callers:

```swift
let backupAPI = WABackup()
let backups = try backupAPI.getBackups()
guard let backup = backups.validBackups.first else {
    throw NSError(domain: "Example", code: 2)
}

try backupAPI.connectChatStorageDb(from: backup)
```

`getBackups()` is retained as the legacy discovery API. It keeps the historical
`validBackups` / `invalidBackups` split. `inspectBackups()` is the recommended
entry point when you need encryption-aware discovery or per-backup diagnostics.

Each `BackupDiscoveryInfo` includes:

- `status` to distinguish `ready`, `encrypted`, and structural failure cases
- `isEncrypted` when `Manifest.plist` exposes `IsEncrypted`
- `isReady` as the high-level boolean gate for chat APIs
- `backup` when the candidate can still be represented as an `IPhoneBackup`

`BackupDiscoveryInfo.backup` is intentionally not part of the JSON contract. It
is the in-memory value you can pass to `connectChatStorageDb(from:)` after
checking `status == .ready`.

If you want exported media and copied profile images:

```swift
let outputDirectory = URL(fileURLWithPath: "/tmp/wa-export", isDirectory: true)
let chats = try backupAPI.getChats(directoryToSavePhotos: outputDirectory)
let payload = try backupAPI.getChat(chatId: chats[0].id, directoryToSaveMedia: outputDirectory)
```

## Command Line Interface

The package also ships with a small companion executable named `SwiftWABackupCLI`. It mirrors the basic workflows exposed by the Python port [PyWABackupAPI](https://github.com/domingogallardo/PyWABackupAPI):

- discover backups with `list-backups`
- list chats with `list-chats`
- export a full chat with `export-chat`

Run it directly from the package root:

```bash
swift run SwiftWABackupCLI --help
```

List backups under the default macOS MobileSync folder:

```bash
swift run SwiftWABackupCLI list-backups \
  --backup-path "$HOME/Library/Application Support/MobileSync/Backup" \
  --json --pretty
```

List chats from a specific backup:

```bash
swift run SwiftWABackupCLI list-chats \
  --backup-path "$HOME/Library/Application Support/MobileSync/Backup" \
  --backup-id "00008101-000478893600801E" \
  --json --pretty
```

Export one chat to JSON and copy message media:

```bash
swift run SwiftWABackupCLI export-chat \
  --backup-path "$HOME/Library/Application Support/MobileSync/Backup" \
  --backup-id "00008101-000478893600801E" \
  --chat-id 44 \
  --output-dir /tmp/chat-44 \
  --pretty
```

Export only the JSON payload to a file:

```bash
swift run SwiftWABackupCLI export-chat \
  --backup-path "$HOME/Library/Application Support/MobileSync/Backup" \
  --backup-id "00008101-000478893600801E" \
  --chat-id 44 \
  --output-json /tmp/chat-44.json \
  --pretty
```

`--output-dir` creates the directory if it does not exist, writes `chat-<id>.json` inside it, and copies exported media into that same directory. `--output-json` writes only the JSON file.

If `--backup-id` is omitted, the CLI uses the first valid backup it finds in the given root directory.

The CLI continues to use the legacy backup discovery flow. If you need
encryption-aware diagnostics, use the library API and inspect backups with
`inspectBackups()` before calling `connectChatStorageDb(from:)`.

## JSON Export

`ChatDumpPayload` is the full chat export payload exposed by the public API and intended for JSON serialization.

`MessageInfo.author` is the single structured sender field exposed by the public API.

For UI and exports:

- use `author` for normal user-authored messages
- do not assume that every message has a phone-bearing real author
- `@lid` is a WhatsApp identifier form seen in modern multi-device contexts; this project treats `LID` as an opaque WhatsApp term and treats `@lid` as distinct from a phone-number JID (`@s.whatsapp.net`)
- when local client-side mapping data is available, for example in caches or databases such as `LID.sqlite`, the runtime may sometimes resolve a `@lid` identity back to a phone-based identity
- in group chats, a direct-chat label that is only a formatted phone number is treated as fallback, so a human-readable push name may be rendered instead to stay aligned with WhatsApp Web

Recommended JSON settings:

- `JSONEncoder.dateEncodingStrategy = .iso8601`
- `JSONEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]`

Example:

```swift
let payload = try backupAPI.getChat(chatId: 44, directoryToSaveMedia: nil)

let encoder = JSONEncoder()
encoder.dateEncodingStrategy = .iso8601
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

let jsonData = try encoder.encode(payload)
let jsonString = String(decoding: jsonData, as: UTF8.self)
print(jsonString)
```

The formal JSON contract is documented in [Docs/JSONContract.md](./Docs/JSONContract.md).

## Media And Profile Images

When an output directory is provided:

- Message media is copied using the original WhatsApp filename when possible
- Chat avatars are copied as `chat_<chatId>.jpg` or `chat_<chatId>.thumb`
- Contact avatars are copied as `<phone>.jpg` or `<phone>.thumb`

You can observe writes through `WABackupDelegate`:

```swift
final class ExportDelegate: WABackupDelegate {
    func didWriteMediaFile(fileName: String) {
        print("Processed media file: \(fileName)")
    }
}

let delegate = ExportDelegate()
backupAPI.delegate = delegate
```

## Error Handling

The package exposes three error families:

- `BackupError` for backup discovery and file-copy issues
- `DatabaseErrorWA` for SQLite connectivity, missing rows, and unsupported schemas
- `DomainError` for higher-level WhatsApp interpretation problems

Example:

```swift
do {
    let chats = try backupAPI.getChats()
    print(chats.count)
} catch let error as BackupError {
    print("Backup error: \(error.localizedDescription)")
} catch let error as DatabaseErrorWA {
    print("Database error: \(error.localizedDescription)")
} catch {
    print("Unexpected error: \(error)")
}
```

## Tests

Comprehensive regression tests are maintained locally because they depend on sensitive private fixtures and should not be published in the public repository.

The public repository is validated in CI with `swift build`.

## Additional Documentation

- [Database reference](./Docs/WhatsAppDatabase/README.md)
- [JSON contract](./Docs/JSONContract.md)

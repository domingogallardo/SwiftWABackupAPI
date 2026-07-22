# SwiftWABackupAPI

`SwiftWABackupAPI` is a Swift package for extracting WhatsApp data from iPhone backups and then exploring it from a regular WhatsApp backup directory. It includes backup-discovery diagnostics for encrypted backups; chat listing and export operate on the extracted WhatsApp copy, not on the original full-device backup. It can be consumed directly from your own Swift tools and apps, or through the included `SwiftWABackupCLI` executable.

For a macOS app built with this package, see [FreeMyChats](https://github.com/domingogallardo/FreeMyChats).

The former Python port, [PyWABackupAPI](https://github.com/domingogallardo/PyWABackupAPI), remains available as legacy code but is no longer maintained. SwiftWABackupAPI is the maintained implementation.

## Privacy Warning

This package is intended for legitimate backup, recovery, export, and personal analysis workflows.

Accessing or processing WhatsApp conversations without the explicit consent of the people involved can violate privacy laws, workplace policies, and WhatsApp terms of service. Make sure you have the legal and ethical right to inspect the data before using this package.

## What The Package Exposes

The public API is split into two phases:

- Discover and inspect iPhone backups with `IPhoneBackupManager`
- Extract WhatsApp's app-group files into a regular directory with `IPhoneBackup.extractWhatsAppBackup(to:)`
- Treat the returned `ExtractedWhatsAppBackup` as the portable WhatsApp backup
- Open the extracted backup with `WhatsAppBackupReader(backup:)` or `ExtractedWhatsAppBackup.openReader()`
- List chats with `WhatsAppBackupReader.getChats(directoryToSavePhotos:)`
- Export a chat with `WhatsAppBackupReader.getChat(chatId:directoryToSaveMedia:)`

Key public types include:

- `IPhoneBackupManager`
- `IPhoneBackupDiscoveryInfo`
- `IPhoneBackupDiscoveryStatus`
- `IPhoneBackup`
- `ExtractedWhatsAppBackup`
- `ExtractedWhatsAppBackupInfo`
- `WhatsAppBackupReader`
- `WABackupProgress`
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
- An extracted WhatsApp backup directory for chat listing and export

For extraction, the selected iPhone backup must be non-encrypted. Use
`IPhoneBackupManager.inspectIPhoneBackups()` if you need an explicit readiness check before copying
WhatsApp data out of the full-device backup.

By default, `IPhoneBackupManager` looks under:

```text
~/Library/Application Support/MobileSync/Backup/
```

On many systems you will need to grant Full Disk Access to the host app or terminal.

## Installation

Add the package dependency in `Package.swift` using the release rule that matches how you publish or consume the package:

```swift
.package(url: "https://github.com/domingogallardo/SwiftWABackupAPI.git", from: "4.0.0")
```

Then add the product to your target dependencies:

```swift
.product(name: "SwiftWABackupAPI", package: "SwiftWABackupAPI")
```

## Basic Usage

The workflow has two distinct phases. First, copy WhatsApp's files out of an
iPhone backup into a regular local directory:

```swift
import Foundation
import SwiftWABackupAPI

// extract-whatsapp-backup.swift
let manager = IPhoneBackupManager()
let inspections = try manager.inspectIPhoneBackups()
guard let backup = inspections.first(where: { $0.status == .ready })?.iPhoneBackup else {
    throw NSError(domain: "Example", code: 1)
}

let extractedDirectory = URL(fileURLWithPath: "/tmp/whatsapp-backup", isDirectory: true)
let extracted = try backup.extractWhatsAppBackup(to: extractedDirectory, overwriteExisting: true)
let backupInfo = try extracted.getBackupInfo()
print("Copied \(backupInfo.copyCounts.copiedFiles) files to \(extracted.url.path)")
```

After that, work only with the extracted WhatsApp directory. This second script
does not need the original iPhone backup:

```swift
import Foundation
import SwiftWABackupAPI

// read-extracted-whatsapp-backup.swift
let extractedDirectory = URL(fileURLWithPath: "/tmp/whatsapp-backup", isDirectory: true)
let extracted = ExtractedWhatsAppBackup(url: extractedDirectory)
let reader = try extracted.openReader()
let chats = try reader.getChats()
let payload = try reader.getChat(chatId: chats[0].id)

print(payload.chatInfo.name)
print(payload.messages.count)
```

If you want exported media and copied profile images, configure an export root
when opening the reader:

```swift
let copyDirectory = URL(fileURLWithPath: "/tmp/MyCopy", isDirectory: true)
let backupDirectory = copyDirectory.appendingPathComponent("Backup", isDirectory: true)
let exportsDirectory = copyDirectory.appendingPathComponent("Exports", isDirectory: true)

let extracted = try backup.extractWhatsAppBackup(to: backupDirectory, overwriteExisting: true)
let reader = try extracted.openReader(exportRootDirectory: exportsDirectory)
let chats = try reader.getChats()
let payload = try reader.getChat(chatId: chats[0].id)
```

The reader creates export subdirectories as needed:

```text
MyCopy/
├── Backup/
└── Exports/
    ├── ChatProfilePhotos/
    └── Chats/
        └── 44/
            └── Media/
```

`ChatProfilePhotos` contains contact and group images referenced by
`ChatInfo.photoFilename`. Media sent inside a conversation is kept separately
under that chat's `Media` directory. A directory supplied directly to
`getChats(directoryToSavePhotos:)` or `getChat(chatId:directoryToSaveMedia:)`
takes precedence over the configured export root. Without either kind of
destination, the reader keeps its previous read-only behavior and does not copy
files.

For a persistent, self-contained chat bundle, use `exportChat`. This writes a
versioned `chat.json` document and copies every available message and contact
file into the chat's own `Media` directory:

```swift
let exported = try reader.exportChat(chatId: chats[0].id)
let reopened = try reader.openExportedChat(chatId: chats[0].id)

print(exported.documentURL.path)
print(reopened.document.messages.count)
```

Once a chat has been exported, `ChatExportStore` can list and open it without
opening—or retaining—the source backup:

```swift
let exports = ChatExportStore(rootDirectory: exportsURL)
let exportedChats = try exports.listExportedChats()
let chat = try exports.openChat(chatId: 44)

print(exportedChats.count)
print(chat.document.messages.count)
```

```text
Exports/
└── Chats/
    └── 44/
        ├── chat.json
        └── Media/
```

The bundle never stores paths to media inside `Backup`; it only names files
copied into its own `Media` directory. Exports are assembled in a temporary
sibling directory and moved into place after validation. Pass
`overwriteExisting: true` to replace an existing bundle atomically.

The source chat list can be compared with the persistent bundle state:

```swift
switch reader.exportState(for: chats[0]) {
case .notExported:
    print("Not exported")
case .exported(let info):
    print("Exported at", info.exportedAt)
case .stale:
    print("The source chat has changed")
case .invalid(let reason):
    print("Invalid export:", reason)
}
```

`ExportedChatDocument.currentSchemaVersion` identifies the JSON contract.
Opening a document with an unsupported schema version fails explicitly.

Long-running operations accept an optional progress handler:

```swift
let extracted = try backup.extractWhatsAppBackup(
    to: extractedDirectory,
    overwriteExisting: true
) { progress in
    if let fraction = progress.fractionCompleted {
        print("\(progress.phase.rawValue): \(Int(fraction * 100))%")
    } else {
        print("\(progress.phase.rawValue): working")
    }
}

let payload = try reader.getChat(
    chatId: chats[0].id
) { progress in
    print(progress.phase.rawValue, progress.completedUnitCount, progress.totalUnitCount ?? -1)
}
```

`WABackupProgress.totalUnitCount == nil` means the operation is still in an
indeterminate phase. When a total is known, `fractionCompleted` is suitable for
a determinate progress bar. Handlers are called synchronously from the operation
that emits them, so UI clients should dispatch updates to the main actor or main
queue as appropriate.

The extracted directory preserves WhatsApp relative paths such as
`ChatStorage.sqlite`, `ContactsV2.sqlite`, `LID.sqlite`, and `Media/...`, so
chat reads and media exports do not need the iPhone backup's `Manifest.db`.
Extraction also creates `.wa-backup/index.sqlite`, `.wa-backup/backup-info.json`,
and `.wa-backup/README.md` inside the extracted copy. The SQLite index documents
portable path-resolution metadata for external tools, while `backup-info.json`
summarizes source metadata, copied files, byte counts, media resolution counts,
and best-effort WhatsApp database row counts. The runtime does not need the
SQLite index for normal reads, but apps can load the JSON summary with
`ExtractedWhatsAppBackup.getBackupInfo()`.

## Command Line Interface

The package also ships with a small companion executable named `SwiftWABackupCLI`:

- discover iPhone backups with `list-iphone-backups`
- list chats with `list-chats`
- inspect extracted backup metadata with `backup-info`
- export a full chat with `export-chat`
- extract WhatsApp's app-group files with `extract-whatsapp-backup`

Run it directly from the package root:

```bash
swift run SwiftWABackupCLI --help
```

Commands that perform longer work render a terminal progress bar on `stderr`
when run interactively, for example:

```text
Copying WhatsApp files [###############-------------] 54% (341/632 entries)
```

Progress output is kept separate from `stdout`, so JSON output and redirected
exports remain parseable.

List iPhone backups under the default macOS MobileSync folder:

```bash
swift run SwiftWABackupCLI list-iphone-backups \
  --iphone-backups-path "$HOME/Library/Application Support/MobileSync/Backup" \
  --json --pretty
```

`list-iphone-backups` reports diagnostic status for each candidate iPhone backup, including
whether it is ready, encrypted, or otherwise unusable. In JSON mode, the
`iPhoneBackups` array exposes `status`, `isEncrypted`, `isReady`, and `issue`.

Extract the WhatsApp app-group tree from an iPhone backup:

```bash
swift run SwiftWABackupCLI extract-whatsapp-backup \
  --iphone-backups-path "$HOME/Library/Application Support/MobileSync/Backup" \
  --iphone-backup-id "00008101-000478893600801E" \
  --output-dir /tmp/whatsapp-backup
```

Use `--overwrite` when you want existing files in the destination to be replaced.

List chats from the extracted WhatsApp backup:

```bash
swift run SwiftWABackupCLI list-chats \
  --whatsapp-backup-path /tmp/whatsapp-backup \
  --json --pretty
```

Print the portable backup summary generated during extraction:

```bash
swift run SwiftWABackupCLI backup-info \
  --whatsapp-backup-path /tmp/whatsapp-backup \
  --pretty
```

Export one chat to JSON and copy message media:

```bash
swift run SwiftWABackupCLI export-chat \
  --whatsapp-backup-path /tmp/whatsapp-backup \
  --chat-id 44 \
  --output-dir /tmp/chat-44 \
  --pretty
```

Export only the JSON payload to a file:

```bash
swift run SwiftWABackupCLI export-chat \
  --whatsapp-backup-path /tmp/whatsapp-backup \
  --chat-id 44 \
  --output-json /tmp/chat-44.json \
  --pretty
```

`--output-dir` creates the directory if it does not exist, writes `chat-<id>.json` inside it, and copies exported media into that same directory. `--output-json` writes only the JSON file.

If `--iphone-backup-id` is omitted for `extract-whatsapp-backup`, the CLI uses the
first ready iPhone backup it finds in the given root directory. `list-chats` and
`export-chat` never read the iPhone backup; they require
`--whatsapp-backup-path`.

## JSON Export

`ChatDumpPayload` is the full chat export payload exposed by the public API and intended for JSON serialization.

`MessageInfo.author` is the single structured sender field exposed by the public API.
For resolved replies, `MessageInfo.replyToPreview` contains a short excerpt of the referenced
message when its text or caption is available.

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
let payload = try reader.getChat(chatId: 44)

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

You can observe writes through `WhatsAppBackupReaderDelegate`:

```swift
final class ExportDelegate: WhatsAppBackupReaderDelegate {
    func didWriteMediaFile(fileName: String) {
        print("Processed media file: \(fileName)")
    }
}

let delegate = ExportDelegate()
reader.delegate = delegate
```

For progress bars, prefer the `progress` handler on `extractWhatsAppBackup`,
`inspectIPhoneBackups`, `getChats`, and `getChat`. The delegate is intentionally
kept as a lightweight media-write notification hook.

## Error Handling

The package exposes three error families:

- `BackupError` for backup discovery and file-copy issues
- `DatabaseErrorWA` for SQLite connectivity, missing rows, and unsupported schemas
- `DomainError` for higher-level WhatsApp interpretation problems

Example:

```swift
do {
    let reader = try ExtractedWhatsAppBackup(path: "/tmp/whatsapp-backup").openReader()
    let chats = try reader.getChats()
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

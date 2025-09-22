# Repository Guidelines

## Project Structure & Module Organization
The Swift package is defined in `Package.swift`; all library code lives in `Sources/SwiftWABackupAPI`, with each domain concept separated into its own Swift file (for example `BackupManager.swift` for orchestration and `ReactionParser.swift` for message metadata). Tests reside in `Tests/SwiftWABackupAPITests/SwiftWABackupAPITests.swift` and rely on fixtures under `Tests/Data`, including `ChatStorage.sqlite` and companion JSON/text exports. When adding new modules, mirror this layout: place production types under `Sources/SwiftWABackupAPI` and stage any supporting sample artefacts in `Tests/Data`.

## Build, Test, and Development Commands
- `swift build` — compile the package locally.
- `swift test` — run the XCTest suite; use `swift test --filter SwiftWABackupAPITests/testChatContacts` to target a single case when iterating.
- `swift package resolve` — refresh dependency pins in `Package.resolved` if you add or update packages.

## Coding Style & Naming Conventions
Follow the Swift API Design Guidelines: `UpperCamelCase` for types and protocols, `lowerCamelCase` for methods, properties, and local variables. Keep indentation at four spaces and wrap method signatures before 120 columns for readability. Group related extensions in dedicated files (e.g. `String+JidHelpers.swift`) and add doc comments for public-facing APIs or non-obvious behaviour. Prefer pure functions in helpers and guard early to reduce nesting.

## Testing Guidelines
Tests use XCTest; name methods with the `testScenario` pattern (see `testChatMessages`). Use fixtures in `Tests/Data` and update expected counts whenever fixture content changes; regenerate derived files via the Python scripts in the same directory when needed. Run `swift test` before pushing and capture notable failures (such as contact count diffs) in the pull request description.

## Commit & Pull Request Guidelines
Craft commits as focused, logical units with imperative summaries similar to the existing history (`Refactor Errors`). Reference related issues in the body when applicable. Before opening a pull request, ensure tests pass, describe behaviour changes, list any new assets added to `Tests/Data`, and note manual verification steps. Include screenshots or log excerpts only when they clarify the change.

## Data Handling Tips
Large WhatsApp backups live under `Tests/Data`; avoid modifying them in place. If you must add anonymised samples, store them beside existing fixtures and document their source in the pull request to keep reproducibility intact.

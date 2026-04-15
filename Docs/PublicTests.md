# Public Tests

The tracked tests under `Tests/SwiftWABackupAPITests/Public/` are the self-contained suite that can ship with the repository.

- Public tests must not depend on the large local backup under `Tests/Data`.
- Synthetic backups created at runtime are allowed.
- JSON contract tests are public only when their expected snapshots live inline in the test file.
- Fixture-backed regression tests stay outside the public folder and remain local-only.
- Any helper used to pseudonymize public test identifiers or other sensitive literals should remain under `Private/`, not in the public tree.

The public backup-discovery coverage now includes both the legacy discovery flow
(`getBackups()`) and the diagnostic flow (`inspectBackups()`), including ready,
encrypted, unknown-encryption, and incomplete-backup cases.

## Running Tests

Public suites run by default:

- `swift test`
- `swift test --filter BackupDiscoveryTests`
- `swift test --filter ChatSmokeTests`
- `swift test --filter MediaExportSmokeTests`
- `swift test --filter ErrorHandlingTests`
- `swift test --filter InternalHelperTests`
- `swift test --filter SampleBackupInvariantTests`
- `swift test --filter ChatDiscoveryInvariantTests`
- `swift test --filter GroupChatInvariantTests`
- `swift test --filter PublicJSONContractTests`

`PublicJSONContractTests` now covers both chat-export payloads and the
diagnostic discovery payload returned by `inspectBackups()`.

Private fixture-backed suites require the large local backup and the opt-in gate:

- `SWIFT_WA_RUN_FULL_FIXTURE_TESTS=1 swift test`
- `SWIFT_WA_RUN_FULL_FIXTURE_TESTS=1 swift test --filter FixtureRegressionTests`
- `SWIFT_WA_RUN_FULL_FIXTURE_TESTS=1 swift test --filter FullFixtureInvariantTests`
- `SWIFT_WA_RUN_FULL_FIXTURE_TESTS=1 swift test --filter WhatsAppWebReactionRegressionTests`

You can also run a single test method with the usual XCTest filter form:

- `swift test --filter PublicJSONContractTests/testMessageInfoJSONContract`

# Public Tests

The tracked tests under `Tests/SwiftWABackupAPITests/Public/` are the self-contained suite that can ship with the repository.

- Public tests must not depend on the large local backup under `Tests/Data`.
- Synthetic backups created at runtime are allowed.
- JSON contract tests are public only when their expected snapshots live inline in the test file.
- Fixture-backed regression tests stay outside the public folder and remain local-only.
- Any helper used to pseudonymize public test identifiers or other sensitive literals should remain under `Private/`, not in the public tree.

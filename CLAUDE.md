# AscendKit

Swift 6.1 CLI toolkit (macOS 14+) for automating App Store release preparation.
Local-first, JSON-first. Does not upload binaries — Xcode Cloud handles that.

## Build & Test

```bash
swift build                              # build
swift test                               # run all tests
swift run AscendKitCLI --help            # run CLI locally
scripts/package-release.sh               # package release archive
```

CI runs on every push/PR via GitHub Actions (`ci.yml`).

## Project Structure

```
Sources/
  AscendKitCore/       # Library — all business logic lives here
    ASC/               #   App Store Connect API client, auth, JWT
    Metadata/          #   Local metadata authoring & linting
    Screenshots/       #   Import, compose, upload pipeline
    Workspace/         #   Release workspace model
    IAP/               #   In-app purchase validation
    Support/           #   Audit logging, secret management, command catalog
  AscendKitCLI/
    main.swift         #   CLI entry point (ArgumentParser-based)

Tests/
  AscendKitCoreTests/  # Unit tests (Testing framework)
  AscendKitCLITests/   # CLI smoke tests

docs/                  # Architecture, security model, agent playbook
scripts/               # Release packaging, Homebrew tap sync
Formula/               # Homebrew formula
```

## Key Patterns

- **Two-target design**: `AscendKitCore` (library) + `AscendKitCLI` (executable). Put logic in Core, not in main.swift.
- **Plan before apply**: Every remote mutation has a corresponding `plan`/`observe` dry-run command.
- **Confirmation required**: Remote ASC operations require `--confirm-remote-mutation`.
- **`--json` everywhere**: All commands support machine-readable JSON output.
- **Workspace model**: Operations are scoped to a release workspace under `.ascendkit/releases/<id>/`.

## Code Conventions

- Swift 6.1 strict concurrency; prefer `async`/`await` over Combine
- PascalCase for types, camelCase for properties/methods
- Use `ArgumentParser` for CLI commands
- Tests use Swift Testing framework (`@Test`, `#expect`)
- No force unwrapping; use proper error handling
- Avoid committing `.ascendkit/`, `.p8` keys, credentials, or screenshots

## Documentation

- Architecture: `docs/architecture.md`
- Security model: `docs/security-model.md`
- Agent playbook (for AI-driven releases): `docs/agent-release-playbook.md`
- Command catalog: `Sources/AscendKitCore/Support/AscendKitCommandCatalog.swift`

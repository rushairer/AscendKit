# Changelog

AscendKit follows [Semantic Versioning](https://semver.org/). During `0.y.z`, the project is usable but still evolving quickly; minor versions may introduce breaking workflow changes when needed, and patch versions are reserved for compatible fixes.

## Unreleased

No unreleased changes.

## 0.34.0 - 2026-05-02

### Changed

- Updated Homebrew install guidance and version reports to use the dedicated `rushairer/homebrew-ascendkit` tap.

## 0.33.0 - 2026-05-02

### Added

- Added a representative app smoke script for v1 release-candidate validation with the installed AscendKit binary.

## 0.32.0 - 2026-05-02

### Added

- Added a v1 release-readiness checklist and tightened README status language around v1 command-surface hardening.

## 0.31.0 - 2026-05-02

### Added

- ASC lookup, build candidate, app lookup, pricing, and IAP validation reports now include the generating AscendKit CLI version for release traceability.

## 0.30.0 - 2026-05-02

### Added

- Metadata lint, diff, ASC mutation plan, request plan, apply result, and status reports now include the generating AscendKit CLI version for metadata release traceability.

## 0.29.0 - 2026-05-02

### Added

- Screenshot capture, local workflow, and upload execution result files now include the generating AscendKit CLI version for artifact-level traceability.

## 0.28.0 - 2026-05-02

### Added

- Screenshot workflow and upload status reports now include the generating AscendKit CLI version for screenshot release traceability.
- Submission readiness, preparation, review-plan, handoff, and execution-result reports now include the generating AscendKit CLI version for review workflow traceability.

## 0.27.0 - 2026-05-02

### Added

- Doctor reports now include the generating AscendKit CLI version for release readiness traceability.
- Intake reports now include the generating AscendKit CLI version for release workspace traceability.

## 0.26.0 - 2026-05-02

### Added

- Workspace status, hygiene, gitignore, and list reports now include the generating AscendKit CLI version for agent handoff traceability.
- Workspace next-step plans now include the generating AscendKit CLI version for agent recovery traceability.

## 0.25.0 - 2026-05-02

### Added

- Release smoke tests now verify CHANGELOG and Homebrew formula version/checksum alignment before public releases.
- Sanitized workspace exports and handoff validation reports now include the generating AscendKit CLI version for agent handoff traceability.

## 0.24.0 - 2026-05-02

### Changed

- `version --json` now reports an installed-CLI verification command that works outside the AscendKit source checkout.

### Added

- CLI smoke tests now guard v1 command-surface docs against retired command examples and ensure stable command groups remain represented in help output.

## 0.23.0 - 2026-05-02

### Changed

- README and automation-boundary docs now use the current v1 command surface instead of legacy placeholders.
- `metadata sync` now returns a migration hint to use `asc metadata plan/apply`; public docs no longer reference it as a workflow command.
- New ASC auth commands now advertise and accept only `env` and `file` secret providers. Existing `keychain` configs are marked unsupported until a verified resolver exists.

## 0.22.0 - 2026-05-02

### Added

- Screenshot capture now imports ordered `XCTAttachment` screenshots from `.xcresult` when UI tests complete without writing raw screenshot files directly.

## 0.21.0 - 2026-05-02

### Changed

- README and review handoff output now use current-release boundary language instead of MVP wording.

## 0.20.0 - 2026-05-02

### Changed

- Agent release playbook now uses the installed `ascendkit` binary instead of source-checkout `swift run` commands.
- `version --json` now reports Homebrew as the primary install command.

### Added

- v1 command-surface document records stable command groups, migration-only fastlane helpers, and disabled boundaries.

## 0.19.0 - 2026-05-02

### Added

- Homebrew formula verification script checks that the committed formula points at the published release archive and SHA-256 digest.

## 0.18.0 - 2026-05-02

### Changed

- README now presents Homebrew as the primary install path and reserves `swift run` for contributor workflows.

## 0.17.0 - 2026-05-02

### Added

- Public-release preflight script runs tests, CLI smoke checks, shell syntax checks, packaging, checksum verification, Homebrew formula validation, whitespace checks, and sensitive marker scanning.

## 0.16.0 - 2026-05-02

### Added

- `ascendkit version [--json]` reports the installed version, platform, release URL, and release install/verify commands.

## 0.15.1 - 2026-05-02

### Fixed

- Installer downloads now use bounded curl retries and a GitHub CLI fallback when available to reduce transient GitHub release download failures.

## 0.15.0 - 2026-05-02

### Added

- Release asset verifier checks GitHub Release assets and performs a temporary installer smoke test after publishing.

## 0.14.0 - 2026-05-02

### Added

- Installer script downloads a GitHub Release archive, verifies the SHA-256 checksum, and installs `ascendkit` onto the local `PATH`.
- CI now validates shell script syntax before packaging release archives.

## 0.13.0 - 2026-05-02

### Added

- Homebrew formula generation now prepares `Formula/ascendkit.rb` from the current release archive and SHA-256 digest.
- Release workflow now uploads the generated Homebrew formula as a release asset.

## 0.12.3 - 2026-05-02

### Fixed

- GitHub Actions now use `actions/checkout@v5` and GitHub CLI release uploads, removing JavaScript action Node.js 20 deprecation annotations.

## 0.12.2 - 2026-05-02

### Fixed

- GitHub Actions now opt into Node.js 24 for JavaScript actions to avoid the Node.js 20 deprecation warning before `v1.0.0`.

## 0.12.1 - 2026-05-02

### Fixed

- README now documents the CI and release GitHub Actions added in `0.12.0`.

## 0.12.0 - 2026-05-02

### Added

- Central command catalog tests now keep CLI help and agent-facing handoff documentation aligned before the `v1.0.0` release candidate.
- `scripts/package-release.sh` builds a release `ascendkit` binary archive and SHA-256 checksum for GitHub Releases distribution.
- GitHub Actions now run CI on pushes and pull requests, and package release archives for `v*` tags.

### Changed

- CLI help is generated from `AscendKitCommandCatalog` instead of a duplicated hand-written usage block.

## 0.11.0 - 2026-05-02

### Added

- `workspace next-steps --workspace PATH [--json]` turns release summary next actions into a priority-sorted, command-oriented plan for agents.

## 0.10.0 - 2026-05-02

### Added

- `workspace validate-handoff --workspace PATH [--export FILE] [--json]` validates whether another agent can safely take over a release workspace, while keeping release blockers separate from handoff blockers.

## 0.9.0 - 2026-05-02

### Added

- `workspace export-summary --workspace PATH --output FILE [--json]` writes a sanitized handoff JSON report without raw release artifacts or absolute workspace paths.

## 0.8.0 - 2026-05-02

### Added

- `workspace gitignore --workspace PATH [--fix] [--json]` checks whether the app project ignores `.ascendkit/` and can append the rule when explicitly requested.

## 0.7.0 - 2026-05-02

### Added

- `workspace hygiene --workspace PATH [--json]` scans release workspaces for local artifacts and secret-like files that must not be committed or shared publicly.
- `workspace summary` now includes a public-commit hygiene blocker when `.ascendkit/`, ASC state, review artifacts, screenshots, private-key markers, or other local release residue are present.

## 0.6.0 - 2026-05-02

### Added

- `screenshots coverage --workspace PATH [--json]` summarizes screenshot coverage by locale, platform, and upload display type.
- `workspace summary` now includes screenshot coverage findings when a workspace has incomplete screenshot coverage.

## 0.5.0 - 2026-05-02

### Added

- `screenshots upload-status --workspace PATH [--json]` summarizes uploaded, failed, deleted, and retryable screenshot upload items without making network requests.
- `asc metadata status --workspace PATH [--json]` summarizes metadata apply/diff freshness, blocking diffs, and release-notes-only diff state.
- `workspace summary` now includes screenshot upload retry next actions and metadata sync next actions when relevant.

## 0.4.0 - 2026-05-02

### Added

- Text App Privacy status output now lists source and findings for manual handoff.
- Submission readiness App Privacy blocker now points agents to `asc privacy status`.
- Review handoff findings now include App Privacy state/source for manual completion.
- Review submission planning now requires App Privacy to be recorded as published before marking manual submission ready.
- App Privacy status JSON now includes `readyForSubmission` and `nextActions`.
- Review handoff now includes App Privacy state, source, readiness, and next actions.
- `workspace summary --workspace PATH [--json]` now summarizes final release readiness and deduplicated next actions for agents.

### Changed

- `submit execute --confirm-remote-submission` is boundary-disabled by default and records a non-executed result instead of attempting remote App Review submission.
- Review-plan findings classify remote submission execution as an explicit boundary rather than an actionable blocker.

## 0.3.0 - 2026-05-01

### Added

- Local screenshot destination discovery and simulator recommendation for capture planning/workflows.
- Local screenshot workflow status report for capture, import, composition, workflow, and upload-plan readiness.
- Screenshot copy template initialization from `screenshot-plan.json` for framed poster title/subtitle editing.
- Screenshot copy refresh that preserves edited titles/subtitles while syncing to the current screenshot plan.
- Persisted screenshot copy linting against imported artifacts before framed poster composition.
- Local screenshot workflow copy refresh/lint when a copy file is supplied.
- Submission readiness gating for framed poster screenshot copy lint.
- Text submission readiness output now lists unsatisfied checklist items.
- Text screenshot upload-plan output now lists planning findings.
- Text screenshot readiness output now lists readiness findings and next actions.
- Text screenshot copy-lint output now lists missing or stale copy entries.
- Text screenshot workflow status output now lists workflow findings.

## 0.2.0 - 2026-05-01

### Added

- Agent release playbook for handing AscendKit to another AI agent without relying on a long one-off prompt.
- App Privacy workspace status, manual Data Not Collected confirmation, and submission readiness gating.
- Local screenshot capture planning that writes deterministic `xcodebuild test` commands without fastlane.
- Local screenshot capture execution with persisted result logs and automatic import manifest refresh.
- Local screenshot workflow command that runs capture planning, capture execution, import refresh, and composition in one deterministic step.

## 0.1.0 - 2026-05-01

Initial public MVP release.

### Added

- Local release workspaces under `.ascendkit/releases/<release-id>`.
- Xcode project intake, release doctor checks, readiness checks, and audit logs.
- Metadata templates, linting, local-vs-ASC diffing, ASC metadata request planning, and guarded metadata apply.
- ASC auth profiles with secret references stored outside the repository.
- ASC app lookup, build lookup, free pricing mutation, native screenshot upload, and guarded review submission execution.
- Screenshot planning, import, fastlane migration import, store-ready copy composition, poster composition, generic device frame composition, and App Store-sized framed poster composition with configurable copy.
- Reviewer information management and review handoff generation.
- Local IAP subscription template validation.

### Known Boundaries

- Binary upload is intentionally out of scope; use Xcode Cloud or Apple's upload tooling.
- App Privacy "Data Not Collected" publishing cannot be completed with an ASC API key in the tested environment because Apple's IRIS privacy endpoint rejects API-key JWT auth.
- Deep MCP integration is intentionally out of scope for this release.

# AscendKit v1 Release Readiness

This checklist defines the final gates before tagging `v1.0.0`.

## Required Gates

- `scripts/preflight-public-release.sh` passes on a clean working tree.
- GitHub CI passes on the release commit.
- GitHub Release workflow publishes the macOS arm64 archive, checksum, installer script, and generated Homebrew formula.
- `scripts/update-homebrew-formula.sh --version VERSION` and `scripts/verify-homebrew-formula.sh --version VERSION` pass after the GitHub Release exists.
- `scripts/sync-homebrew-tap.sh --commit --push` publishes the verified formula to `rushairer/homebrew-ascendkit`.
- Homebrew reinstall from the synced formula reports the tagged version with `ascendkit --version`.
- `ascendkit version --json` points at the tagged GitHub Release URL.
- `scripts/v1-representative-app-smoke.sh --app-root PATH` passes against a representative app project using the installed binary.
- `scripts/v1-release-readiness.sh --version VERSION --app-root PATH` passes for the published release.
- A representative app project can run `intake inspect`, `doctor release`, `metadata lint`, screenshot workflow status, ASC status commands, and `submit readiness` without source-checkout assumptions.
- README Current Status, install examples, command examples, safety boundaries, and maintainer workflow match the tagged release.
- `docs/v1-command-surface.md`, `docs/automation-boundaries.md`, and `docs/agent-release-playbook.md` remain aligned with the installed `ascendkit` binary.

## Boundary Gates

- Binary upload remains out of scope.
- Archive, signing, or export replacement remains out of scope.
- Xcode Cloud replacement remains out of scope.
- Deep MCP integration remains out of scope.
- Hidden Apple ID web-session automation remains out of scope.
- Remote review submission execution remains boundary-disabled.
- Fastlane commands remain migration helpers only and are not required for the core workflow.

## Public Safety Gates

- No `.ascendkit/` workspace artifacts are committed.
- No `.p8`, `.pem`, `.key`, reviewer credentials, app screenshots, app binaries, or real ASC secrets are committed.
- Sensitive marker scan findings are limited to scanner rules, README examples, test fixtures, and security docs.
- Agent handoff uses `workspace export-summary`, `workspace validate-handoff`, and `workspace next-steps` instead of raw workspace sharing.

## v1 Status Language

At the `v1.0.0` tag, README must describe the v1 command surface as stable for `1.x` except for SemVer-compatible additions. It must not describe command shapes as release-candidate hardening or still evolving before `1.0.0`.

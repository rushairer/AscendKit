# AscendKit v1 Command Surface

This document defines the public command surface that remains stable for `1.x`.

Final release gates are tracked in `docs/v1-release-readiness.md`.

## Install and Runtime Assumption

Normal users and release agents should run the installed binary:

```bash
ascendkit --help
ascendkit version --json
```

`swift run ascendkit ...` is a contributor-only source checkout workflow. It should not appear in normal user quick starts or agent release playbooks.

## Stable v1 Command Groups

These command groups are expected to remain available through `v1.x`:

- `version`
- `agent`
- `workspace`
- `intake`
- `doctor`
- `metadata`
- `screenshots`
- `asc auth`
- `asc lookup`
- `asc apps`
- `asc builds`
- `asc metadata`
- `asc pricing`
- `asc privacy`
- `submit`
- `iap`

Flag names used in README examples and `docs/agent-release-playbook.md` should be treated as v1-stable. Breaking workflow changes require a new major version.

## Migration Compatibility Commands

The following commands are supported as migration helpers, not as the primary workflow:

- `metadata import-fastlane`
- `screenshots import-fastlane`

They should remain documented as optional migration paths only. AscendKit must not require fastlane at runtime for the core release workflow.

## Boundary-Disabled Commands

`submit execute --confirm-remote-submission` is intentionally boundary-disabled. It records non-execution and tells the user to complete final submit-for-review manually in App Store Connect.

Do not enable remote review submission execution in `1.x` without a deliberate scope change and explicit safety review.

## Out-of-Scope for 1.x

These remain out of scope:

- Binary upload.
- Archive, signing, or export replacement.
- Xcode Cloud replacement.
- Deep MCP integration.
- Hidden Apple ID web-session automation.
- Remote review submission execution.

## Documentation Invariants

Before each public release:

- `README.md` Current Status must match `AscendKitVersion.current`.
- README install examples should be Homebrew-first.
- `docs/agent-release-playbook.md` should use installed `ascendkit` commands, not `swift run`.
- `Formula/ascendkit.rb` must point at the published GitHub Release archive digest.
- `ascendkit --help` must remain aligned with README command examples and this document.

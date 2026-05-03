# AscendKit Post-v1 Roadmap

This roadmap keeps the v1 command surface stable while improving distribution, reliability, and agent handoff quality.

## v1.0.x Stability Line

- Keep Homebrew as the primary distribution path.
- Fix release-process issues without changing workflow semantics.
- Keep README, formula, release assets, and tap state aligned for every public release.
- Keep checksum and stale-tap troubleshooting executable through `scripts/diagnose-homebrew-install.sh` so users can recover without reading maintainer notes.

## v1.1 Distribution Hardening

- Publish a macOS universal archive that supports both Apple Silicon (`arm64`) and Intel (`x86_64`).
- Make Homebrew formula and direct installer prefer the universal archive.
- Keep architecture-specific archive fallback support in the installer for older releases or emergency builds.
- Verify release assets, Homebrew formula, Homebrew reinstall, and representative-app smoke through `scripts/v1-release-readiness.sh`.

## v1.2 Screenshot and ASC Reliability

- Expand local screenshot upload status so ASC delivery failures and pending processing are visible without network requests.
- Emit deterministic screenshot upload recovery commands that agents can follow without guessing the next safe step.
- Surface screenshot upload recovery and ready-for-review commands through workspace summary and next-steps.
- Harden screenshot upload and replacement recovery paths with clearer persisted status.
- Improve retry diagnostics for partial ASC failures.
- Expand real-project coverage around existing remote screenshot sets, ordering, and deletion safety.

## v1.3 Agent Handoff Productization

- Keep `docs/agent-release-playbook.md` as the single source of truth for AI-agent operation.
- Generate short, copyable handoff prompts with `scripts/create-agent-handoff-prompt.sh` instead of relying on long one-off prompts.
- Improve `workspace export-summary`, `workspace validate-handoff`, and `workspace next-steps` for shorter agent prompts.
- Consider a thin Codex Skill only after the CLI and playbook remain stable across repeated real app releases.

## v1.4 Distribution Checksum Safety

- Prevent Homebrew formula updates from accidentally using a locally rebuilt archive checksum after a GitHub Release already exists.
- Prefer published release asset digests, then downloaded published release assets, before falling back to local package checksums for unreleased versions.
- Keep checksum mismatch recovery documented and executable through `scripts/diagnose-homebrew-install.sh`.

## Long-term Boundaries

- Binary upload remains low priority and out of scope for the current roadmap.
- Xcode Cloud remains the preferred binary delivery path.
- Remote final submit-for-review execution remains disabled unless the safety model is explicitly revisited.
- Deep MCP integration remains out of scope until local CLI workflows are fully reliable.

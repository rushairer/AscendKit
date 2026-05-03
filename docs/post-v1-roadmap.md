# AscendKit Post-v1 Roadmap

This roadmap keeps the v1 command surface stable while improving distribution, screenshot quality, release reliability, and agent handoff quality. The deeper product direction is tracked in `docs/app-store-growth-copilot-roadmap.md`.

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

## v1.5 Release Finalization Safety

- Treat the GitHub Release workflow as the authoritative publisher of release assets.
- Finalize Homebrew only after the release workflow has completed so the formula uses the final published asset digest.
- Provide one maintainer command that refreshes the formula, verifies the published digest, syncs the tap, and optionally reinstalls and diagnoses Homebrew.
- Keep the finalizer local and explicit; it must not upload binaries, submit App Store reviews, or mutate App Store Connect.

## v1.6 Screenshot Doctor and UI Test Scaffold

- Detect whether a project has a repeatable screenshot automation path.
- Guide users and AI Agents toward UI-test-driven screenshots when deterministic capture is missing.
- Scaffold starter UI Test code and launch-argument guidance without hardcoding app-specific data.
- Keep manual screenshot import as a supported fallback.

## v1.7 iOS/iPadOS Screenshot Studio

- Make iOS and iPadOS the first polished screenshot platform tier.
- Add an explicit device-frame registry and screenshot requirement matrix.
- Improve framed and poster-style composition presets.
- Lint locale, display-size, screenshot copy, and first-impression coverage.

## v1.8 Cross-Platform Screenshot Expansion

- Publish an honest platform support matrix for iOS, iPadOS, macOS, visionOS, tvOS, and watchOS.
- Add macOS and visionOS screenshot lint/composition baselines.
- Add tvOS and watchOS import/lint baselines before claiming full capture support.
- Emit actionable unsupported-feature diagnostics instead of silent gaps.

## v1.9 Read-Only ASC Analytics Reports

- Fetch and normalize App Store Connect analytics and sales reports into local snapshots.
- Generate Markdown/JSON reports for post-launch trends, caveats, and anomalies.
- Connect report findings to screenshot, metadata, pricing, and release-note experiment recommendations.
- Keep analytics read-only; no automatic pricing, campaign, metadata, or review-submission mutations.

## v2.0 App Store Growth Copilot

- Close the loop from release preparation to post-launch insight and next-release recommendations.
- Combine release workspace history, screenshots, metadata, and analytics into a safe local growth workflow.
- Generate agent handoff plans for the next App Store iteration.

## Long-term Boundaries

- Binary upload remains low priority and out of scope for the current roadmap.
- Xcode Cloud remains the preferred binary delivery path.
- Remote final submit-for-review execution remains disabled unless the safety model is explicitly revisited.
- Deep MCP integration remains out of scope until local CLI workflows are fully reliable.

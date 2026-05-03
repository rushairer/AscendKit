# AscendKit App Store Growth Copilot Roadmap

This roadmap turns AscendKit from a release-preparation CLI into a local-first App Store Release and Growth Copilot. It keeps the current safety boundaries: no binary upload replacement, no Xcode Cloud replacement, no remote final review submission execution, and no deep MCP dependency.

## Product Thesis

Independent developers and small teams do not only need help uploading metadata. They need a repeatable loop:

1. Prepare release assets.
2. Generate persuasive screenshots.
3. Sync App Store metadata safely.
4. Submit with clear human handoff.
5. Read post-launch App Store data.
6. Convert data into the next screenshot, copy, pricing, or product iteration.

AscendKit should own this loop around App Store release assets and insights while leaving binary delivery to Xcode Cloud and final high-risk decisions to humans.

## Current Capability Assessment

### Strong foundations

- Local release workspace and audit model.
- Metadata import, lint, diff, and App Store Connect apply planning.
- Screenshot import, composition, upload planning, and native ASC screenshot upload execution.
- Device-frame and poster-style screenshot composition primitives.
- Homebrew distribution and release finalization safety.
- Agent handoff commands and release-readiness gates.

### Current gaps

- Screenshot workflows are still engineering-heavy for users who have never written UI Tests.
- Platform support is not yet a clear product matrix across iOS, iPadOS, macOS, watchOS, tvOS, and visionOS.
- Device-frame support exists as a capability but not yet as a polished catalog with explicit device/platform coverage.
- Screenshot intelligence is not yet connected to a guided UI Test scaffold.
- ASC API usage is focused on release preparation, not post-launch analytics, anomaly detection, or growth recommendations.

## Strategic Pillars

### Pillar 1: Screenshot Studio

Make screenshots a core product capability, not a side effect of tests.

Target outcomes:

- A user without UI Test experience can generate a screenshot plan and scaffold deterministic UI Tests.
- An AI Agent can inspect the workspace and know when to suggest UI-test-driven screenshot generation.
- iOS and iPadOS screenshot coverage becomes polished enough to be a reference workflow.
- Additional Apple platforms are supported through explicit tiers instead of vague claims.
- Device frames become a versioned, inspectable, and legally safe registry.

### Pillar 2: Release Safety

Keep public releases and user app submissions deterministic, auditable, and reversible.

Target outcomes:

- Every published AscendKit release is reproducible through Homebrew and direct installer diagnostics.
- Remote App Store Connect mutations stay explicit and require confirmation.
- Final review submission execution remains boundary-disabled until the safety model is revisited.

### Pillar 3: App Store Analytics and Growth

Use read-only App Store Connect reporting to help developers understand what happened after launch.

Target outcomes:

- Fetch App Store Analytics and Sales reports into local snapshots.
- Generate weekly Markdown/JSON reports for downloads, product page conversion, revenue, and retention-oriented signals where available.
- Detect anomalies such as conversion drops, download drops, revenue drops, refund spikes, and post-release regressions.
- Connect analytics findings back to screenshot, metadata, pricing, and release notes recommendations.

## Platform Support Policy

Do not claim full support for all Apple platforms until each platform has a documented capture, lint, composition, and upload story.

### Tier 1: iOS and iPadOS

Scope:

- UI-test-driven capture.
- Import from xcresult and raw files.
- Required App Store screenshot size linting.
- Locale and device coverage linting.
- Device-frame and poster-style composition.
- ASC upload plan and explicit upload execution.

Quality bar:

- A non-expert user can follow AscendKit guidance from project inspection to composed screenshots.
- Three can remain the representative regression app for the workflow.

### Tier 2: macOS and visionOS

Scope:

- Project and scheme discovery.
- Capture/import support.
- Size and locale linting.
- Basic composition templates.
- ASC upload planning where platform resources are available.

Quality bar:

- Stable enough for developers to validate coverage and produce acceptable store assets.
- Device-frame polish can lag behind iOS/iPadOS.

### Tier 3: tvOS and watchOS

Scope:

- Store screenshot requirement documentation.
- Import, lint, and manifest support.
- Upload planning where ASC resource mapping is confirmed.

Quality bar:

- AscendKit should help users avoid missing or malformed assets.
- Full capture and frame composition are lower priority until Tier 1 and Tier 2 are reliable.

## Device Frame Strategy

Implement a frame registry instead of hardcoding one-off layouts.

Required registry fields:

- Platform.
- Device family.
- Marketing device name.
- Screen pixel size.
- Supported orientations.
- Frame asset source.
- Content inset.
- Corner radius.
- Shadow and background defaults.
- Legal/source note.

Initial catalog:

- iPhone current App Store representative size.
- iPad current App Store representative size.
- Mac screenshot card frame.

Expansion rules:

- Add frames only when they can be tested by deterministic rendering tests.
- Prefer user-supplied or separately maintained assets if bundled frame assets create licensing risk.
- Keep poster-style composition as the fallback when explicit device frames are unavailable.

## UI Test Guidance Strategy

AscendKit must not assume users already know UI Tests. It should teach and scaffold the minimum repeatable path.

Required capabilities:

- `screenshots doctor`: detect UI test target, testable scheme, simulator destinations, launch argument support, and screenshot output paths.
- `screenshots scaffold-uitests`: generate starter UI Test code and a screenshot plan without changing product behavior.
- `screenshots plan`: propose screenshot-worthy flows from structured product inputs.
- `screenshots capture`: run xcodebuild test and import raw screenshots or xcresult attachments.
- `screenshots lint`: verify screenshot count, size, locale, platform, order, and composition readiness.

Agent guidance:

- Generated handoff prompts should explicitly tell AI Agents to use UI Tests when deterministic screenshots are missing.
- Prompts should instruct agents to use launch arguments, stable mock data, deterministic navigation, and no real credentials.
- Prompts should preserve the option to import manual screenshots when UI Tests are not yet practical.

## ASC Analytics Strategy

ASC analytics work should start as read-only. The first useful product is a local report, not an automated optimizer.

Initial commands:

- `analytics fetch`: download App Store Connect analytics and sales report data into local snapshots.
- `analytics snapshot`: normalize reports into local JSON summaries.
- `analytics report`: generate Markdown and JSON reports.
- `analytics alert`: detect threshold-based anomalies.
- `analytics recommend`: propose release asset or metadata experiments based on findings.

Initial report sections:

- App Store impressions and product page views where available.
- Product page conversion rate where available.
- Downloads and redownloads.
- Sales, proceeds, refunds, and subscription indicators where available.
- Version adoption and post-release trend changes where available.
- Data availability caveats, privacy threshold caveats, and platform caveats.

Safety rules:

- No automatic price changes.
- No automatic ad or campaign changes.
- No automatic App Store metadata mutation from analytics recommendations.
- No claim of causality unless the report has an explicit before/after release or experiment basis.

## Milestones

### v1.5.0: Release Finalization Safety

Outcome:

- Public AscendKit releases can be finalized after GitHub Release workflow completion without checksum drift.

Deliverables:

- `scripts/finalize-homebrew-release.sh` documented and verified.
- README release checklist simplified around the finalizer.
- One real release proves the finalizer path.

Acceptance:

- Homebrew formula, tap, GitHub Release asset digest, and installed binary are aligned.
- `scripts/v1-release-readiness.sh --version VERSION --app-root PATH` passes after finalization.

### v1.6.0: Screenshot Doctor and UI Test Scaffold

Outcome:

- A user or AI Agent can discover why screenshots are not repeatable and generate a starter UI Test path.

Deliverables:

- `screenshots doctor` report model.
- UI test target and scheme detection.
- Simulator destination recommendations grouped by platform.
- Launch argument and screenshot output strategy guidance.
- `screenshots scaffold-uitests` starter template for Swift/XCTest.
- Agent handoff prompt update that recommends UI-test-driven screenshot generation when needed.

Acceptance:

- Three can run from no screenshot automation guidance to a generated plan and starter UI Test scaffold.
- Generated scaffold avoids real credentials and does not require app-specific hardcoding in AscendKit.

### v1.7.0: iOS/iPadOS Screenshot Studio

Outcome:

- iOS and iPadOS screenshots become a polished, repeatable App Store asset pipeline.

Deliverables:

- iOS/iPadOS screenshot requirement matrix.
- Device-frame registry MVP.
- Framed and poster-style template presets.
- Locale and display-size coverage lint.
- Screenshot copy lint and first-impression warnings.
- Regression fixtures for raw, framed, and poster outputs.

Acceptance:

- Three can produce store-ready iPhone and iPad composed screenshots through a documented local workflow.
- Missing screenshot size, locale, or copy coverage produces deterministic next steps.

### v1.8.0: Cross-Platform Screenshot Expansion

Outcome:

- AscendKit can honestly communicate platform support tiers.

Deliverables:

- macOS screenshot lint and composition baseline.
- visionOS screenshot lint and composition baseline.
- tvOS/watchOS import and lint baseline.
- Platform support matrix in README and docs.
- Per-platform unsupported-feature diagnostics instead of silent gaps.

Acceptance:

- Each platform has explicit supported, partial, and unsupported capabilities.
- Users receive actionable fallbacks when capture or frames are not supported.

### v1.9.0: Read-Only ASC Analytics Reports

Outcome:

- AscendKit can generate post-launch App Store performance reports without mutating remote state.

Deliverables:

- ASC analytics and sales report auth reuse.
- Local analytics snapshot model.
- Markdown/JSON report generator.
- Threshold-based anomaly alerts.
- Release-to-report correlation using workspace release history.

Acceptance:

- A developer can run a weekly local report and see trends, caveats, and recommended next experiments.
- Analytics recommendations never mutate App Store Connect.

### v2.0.0: App Store Growth Copilot

Outcome:

- AscendKit closes the loop from release preparation to post-launch insight and next release recommendations.

Deliverables:

- Unified release and growth dashboard summary.
- Screenshot and metadata experiment recommendation model.
- Analytics-informed screenshot plan updates.
- Agent handoff flow for the next release cycle.

Acceptance:

- A user can hand an app workspace to an AI Agent and get a safe, auditable plan for the next App Store iteration.

## Immediate Next Engineering Slice

Start v1.6.0 with the smallest useful screenshot doctor foundation:

1. Add a local screenshot doctor model that can report UI test target presence, scheme hints, simulator destination hints, screenshot source status, and recommended next commands.
2. Expose it through a dry-run CLI command without mutating project files.
3. Add tests using synthetic project fixtures.
4. Update agent handoff docs so agents recommend UI Tests only when deterministic screenshot automation is missing.

Do not start ASC analytics implementation until v1.6 and v1.7 screenshot workflows are stable.

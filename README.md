# AscendKit

AscendKit is a local-first Swift toolkit for preparing App Store releases. It helps Apple platform teams organize release workspaces, inspect projects, lint App Store metadata, prepare screenshots, compare local metadata with App Store Connect, and execute a guarded review-submission workflow.

The project is designed for AI-assisted release work without handing raw secrets or mutable App Store state directly to an agent. AscendKit keeps release state in deterministic local files, stores only secret references, and requires explicit confirmation flags before remote App Store Connect mutations.

## Current Status

Current documented release: `v1.0.0`.

AscendKit follows [Semantic Versioning](https://semver.org/). The v1 command surface is stable for `1.x`: breaking workflow changes require a new major version, while compatible commands, flags, diagnostics, and documentation can continue to evolve through minor releases.

AscendKit has been used end-to-end on real iOS app release workflows covering local screenshot preparation, metadata, pricing, reviewer information, build selection, screenshot upload, and guarded App Review handoff. App Privacy publishing is currently documented as a boundary where Apple's IRIS endpoint may require App Store Connect UI or future Apple ID web-session support.

Implemented today:

- Swift Package with `AscendKitCore` and the `ascendkit` CLI.
- Durable release workspaces under `.ascendkit/releases/<release-id>`.
- Project intake and release doctor checks.
- Metadata templates, fastlane metadata import, linting, diffing, and ASC request planning.
- Screenshot planning, import manifests, fastlane screenshot import, local composition outputs, guarded ASC upload planning, and native screenshot upload execution.
- App Store Connect auth profiles using secret references.
- ASC app lookup, build lookup, metadata observation, metadata apply, and guarded review handoff.
- Reviewer information, readiness checks, review handoff, and submission result persistence.
- Local IAP subscription template validation.

Out of scope for the current release:

- Binary upload.
- Archive/sign/export replacement.
- Xcode Cloud replacement.
- Deep MCP integration.
- Fully managed App Store Connect pricing/App Privacy abstractions for every Apple API edge case.
- Broad remote screenshot lifecycle management beyond guarded replace-existing deletion.

`v1.0.0` release readiness is tracked in `docs/v1-release-readiness.md`.

## Requirements

- macOS 14 or later.
- Xcode command line tools for project inspection, simulator discovery, local screenshot capture, and release diagnostics.
- An App Store Connect API key for remote ASC operations.
- Optional: `fastlane` only if you are migrating existing metadata or screenshot folders. It is not required for the core workflow.
- Optional for contributors: Swift 6.1 or later when building from source.

## Installation

Prefer Homebrew for normal use:

```bash
brew tap rushairer/ascendkit
brew install ascendkit
ascendkit --version
ascendkit --help
ascendkit version --json
```

After installation, run `ascendkit` from any app project directory. User-facing documentation assumes this installed binary.

Alternative direct installer from a source checkout or release asset:

```bash
scripts/install-ascendkit.sh --version 1.0.0
ASCENDKIT_INSTALL_DIR=/usr/local/bin scripts/install-ascendkit.sh
```

The installer downloads the macOS arm64 release archive from GitHub Releases, verifies the `.sha256` digest with `shasum`, and installs only the `ascendkit` CLI binary. Use it when Homebrew is unavailable or when validating a specific release asset.

Verify a published release before announcing it:

```bash
scripts/verify-release-assets.sh --version 1.0.0
```

The verifier checks for the expected GitHub Release assets and performs a temporary installer smoke test.

Run the v1 representative app smoke against a local app project before a public release:

```bash
scripts/v1-representative-app-smoke.sh --app-root /path/to/YourApp
```

The smoke uses the installed `ascendkit` binary from `PATH`, creates a local `.ascendkit/` release workspace in the target app, and exercises intake, doctor, metadata lint, screenshot workflow status, ASC local status, submission readiness, and agent handoff commands without remote mutations.

GitHub release archives are generated with:

```bash
scripts/package-release.sh
cd dist && shasum -a 256 -c ascendkit-*.tar.gz.sha256
```

The archive contains only the AscendKit CLI, the installer script, `LICENSE`, `README.md`, and install instructions. It does not contain app workspaces, App Store Connect credentials, screenshots, or app binaries.

Homebrew formula maintenance:

```bash
scripts/update-homebrew-formula.sh
scripts/verify-homebrew-formula.sh --version 1.0.0
scripts/sync-homebrew-tap.sh --commit --push
scripts/v1-release-readiness.sh --version 1.0.0 --app-root /path/to/RepresentativeApp
ruby -c Formula/ascendkit.rb
```

The generated formula points at the GitHub Release archive for the current `ascendkit --version`. If the matching GitHub Release exists, the script uses the uploaded release asset digest; otherwise it falls back to the local package checksum. After a release workflow succeeds, run `scripts/update-homebrew-formula.sh` again and commit any checksum update so `Formula/ascendkit.rb` matches the published asset digest. Then sync the dedicated `rushairer/homebrew-ascendkit` tap with `scripts/sync-homebrew-tap.sh --commit --push`. Maintainers should keep both formula copies aligned with every public release so users can install with `brew install ascendkit`.

For development, run from the source checkout:

```bash
swift test
swift run ascendkit --help
swift run ascendkit --version
swift run ascendkit version --json
```

If you are handing AscendKit to another AI agent, start with `docs/agent-release-playbook.md`. Use a short prompt plus that playbook; do not rely on a long one-off prompt as the only operating manual.

## Quick Start: Submit an App Store Release

The typical flow is:

1. Inspect the app project and create a release workspace.
2. Add or import metadata.
3. Prepare screenshots locally.
4. Configure App Store Connect auth.
5. Observe remote ASC state.
6. Plan and apply metadata.
7. Select a build.
8. Plan and upload screenshots with explicit confirmation, or use App Store Connect UI when replacing existing screenshots.
9. Add reviewer information.
10. Run readiness checks.
11. Generate a review handoff and complete final submission manually in App Store Connect.

Set a few shell variables first:

```bash
APP_ROOT=/path/to/YourApp
RELEASE_ID=appstore-1.0
WORKSPACE="$APP_ROOT/.ascendkit/releases/$RELEASE_ID"
```

Create the workspace:

```bash
ascendkit intake inspect \
  --root "$APP_ROOT" \
  --release-id "$RELEASE_ID" \
  --save
```

Create metadata templates, or import existing fastlane metadata:

```bash
ascendkit metadata init --workspace "$WORKSPACE" --locale en-US

ascendkit metadata import-fastlane \
  --workspace "$WORKSPACE" \
  --source "$APP_ROOT/fastlane/metadata"
```

Lint metadata:

```bash
ascendkit metadata status --workspace "$WORKSPACE"
ascendkit metadata lint --workspace "$WORKSPACE" --locale en-US --json
```

Import screenshots from a folder or from fastlane:

```bash
ascendkit screenshots import \
  --workspace "$WORKSPACE" \
  --source /path/to/screenshots

ascendkit screenshots import-fastlane \
  --workspace "$WORKSPACE" \
  --source "$APP_ROOT/fastlane/screenshots" \
  --locales en-US,zh-Hans
```

Compose local screenshot artifacts:

```bash
ascendkit screenshots copy init --workspace "$WORKSPACE" --locale en-US
ascendkit screenshots copy refresh --workspace "$WORKSPACE" --locale en-US
ascendkit screenshots copy lint --workspace "$WORKSPACE" --locale en-US
ascendkit screenshots compose --workspace "$WORKSPACE" --mode storeReadyCopy
ascendkit screenshots compose --workspace "$WORKSPACE" --mode deviceFrame
ascendkit screenshots compose --workspace "$WORKSPACE" --mode poster
```

Run the local Xcode UI-test screenshot workflow without fastlane:

```bash
ascendkit screenshots destinations --workspace "$WORKSPACE" --json
ascendkit screenshots copy init --workspace "$WORKSPACE" --locale en-US --json
ascendkit screenshots copy refresh --workspace "$WORKSPACE" --locale en-US --json
ascendkit screenshots copy lint --workspace "$WORKSPACE" --locale en-US --json

ascendkit screenshots workflow run \
  --workspace "$WORKSPACE" \
  --scheme MyApp \
  --mode framedPoster \
  --copy "$WORKSPACE/screenshots/copy/en-US.json" \
  --json

ascendkit screenshots workflow status --workspace "$WORKSPACE" --json
```

Save an ASC auth profile. The profile stores only a reference to the private key file, not the key content:

```bash
ascendkit asc auth save-profile \
  --name default \
  --issuer-id ASC_ISSUER_ID \
  --key-id ASC_KEY_ID \
  --private-key-provider file \
  --private-key-ref /secure/path/AuthKey_KEYID.p8
```

Attach that profile to the release workspace:

```bash
ascendkit asc auth init \
  --workspace "$WORKSPACE" \
  --profile default

ascendkit asc auth check --workspace "$WORKSPACE" --json
```

Observe the app and remote metadata:

```bash
ascendkit asc lookup plan --workspace "$WORKSPACE" --json
ascendkit asc apps lookup --workspace "$WORKSPACE" --json
ascendkit asc metadata observe --workspace "$WORKSPACE" --json
```

Plan and upload screenshots. By default, the plan reads observed ASC screenshot sets and blocks execution when matching remote screenshots already exist. If you intend to replace existing screenshots, add `--replace-existing` to the plan and upload commands so AscendKit records and executes explicit screenshot deletions before uploading new assets:

```bash
ascendkit screenshots upload-plan --workspace "$WORKSPACE" --json

ascendkit screenshots upload-plan \
  --workspace "$WORKSPACE" \
  --replace-existing \
  --json

ascendkit screenshots upload \
  --workspace "$WORKSPACE" \
  --replace-existing \
  --confirm-remote-mutation \
  --json

ascendkit screenshots upload-status --workspace "$WORKSPACE" --json
```

Plan and apply metadata changes:

```bash
ascendkit metadata diff --workspace "$WORKSPACE" --json
ascendkit asc metadata plan --workspace "$WORKSPACE" --json
ascendkit asc metadata requests --workspace "$WORKSPACE" --json

ascendkit asc metadata apply \
  --workspace "$WORKSPACE" \
  --confirm-remote-mutation \
  --json
```

Set the app price to free through the official App Store Connect API:

```bash
ascendkit asc pricing set-free --workspace "$WORKSPACE" --json

ascendkit asc pricing set-free \
  --workspace "$WORKSPACE" \
  --confirm-remote-mutation \
  --json
```

Observe builds and select a processed build:

```bash
ascendkit asc builds observe --workspace "$WORKSPACE" --json
ascendkit asc builds list --workspace "$WORKSPACE" --json
```

Add reviewer information. If no login is required, omit login credentials and leave `--requires-login` false:

```bash
ascendkit submit review-info set \
  --workspace "$WORKSPACE" \
  --first-name "Ada" \
  --last-name "Lovelace" \
  --email "review@example.com" \
  --phone "+15555555555" \
  --notes "No login required. Please launch the app and continue through onboarding." \
  --requires-login false
```

Prepare the submission and review the handoff:

```bash
ascendkit doctor release --workspace "$WORKSPACE" --json
ascendkit submit readiness --workspace "$WORKSPACE" --json
ascendkit submit prepare --workspace "$WORKSPACE" --json
ascendkit submit review-plan --workspace "$WORKSPACE" --json
ascendkit submit handoff --workspace "$WORKSPACE"
```

Use the handoff to complete the final submit-for-review action manually in App Store Connect. Remote review submission execution is boundary-disabled in the current release, even when `--confirm-remote-submission` is passed.

## Command Reference

All commands support `--json` where shown in `ascendkit --help`. JSON output is intended for scripts, CI, and AI-agent wrappers.

### `workspace`

Inspect existing release workspace state.

```bash
ascendkit workspace status --workspace "$WORKSPACE"
ascendkit workspace status --workspace "$WORKSPACE" --json
ascendkit workspace summary --workspace "$WORKSPACE" --json
ascendkit workspace hygiene --workspace "$WORKSPACE" --json
ascendkit workspace gitignore --workspace "$WORKSPACE" --json
ascendkit workspace gitignore --workspace "$WORKSPACE" --fix --json
ascendkit workspace export-summary --workspace "$WORKSPACE" --output /tmp/ascendkit-summary.json --json
ascendkit workspace validate-handoff --workspace "$WORKSPACE" --export /tmp/ascendkit-summary.json --json
ascendkit workspace next-steps --workspace "$WORKSPACE" --json
```

`workspace status` shows which expected files exist, such as manifest, metadata, screenshots, ASC auth, readiness, and review artifacts. `workspace summary` reads the persisted release artifacts and emits final readiness state plus deduplicated next actions for agents. `workspace hygiene` checks whether the local workspace contains release artifacts or potential secrets that must not be committed. `workspace gitignore` checks whether the app project's `.gitignore` excludes `.ascendkit/`; add `--fix` to append the rule. `workspace export-summary` writes a sanitized handoff JSON file that excludes raw screenshots, ASC auth, metadata, review artifacts, audit log contents, and absolute workspace paths. The export includes `ascendKitVersion` so the receiving agent can verify which CLI generated the handoff. `workspace validate-handoff` checks whether another agent can safely take over the release workflow; release blockers are reported as warnings because they are work for the receiving agent, not handoff blockers. `workspace next-steps` converts summary next actions into a priority-sorted, command-oriented plan.

```bash
ascendkit workspace audit --workspace "$WORKSPACE"
```

Reads the workspace audit log. Sensitive values are redacted before they are written.

```bash
ascendkit workspace list --root "$APP_ROOT"
```

Lists known release workspaces under an app root.

### `intake`

Create or update the release manifest from an Apple project.

```bash
ascendkit intake inspect \
  --root "$APP_ROOT" \
  --release-id "$RELEASE_ID" \
  --save \
  --json
```

Useful options:

- `--root PATH`: app repository root.
- `--project PATH`: specific `.xcodeproj` or project folder.
- `--workspace PATH`: existing release workspace.
- `--release-id ID`: release workspace identifier.
- `--save`: persist the discovered manifest.

### `doctor`

Run release hygiene checks.

```bash
ascendkit doctor release --workspace "$WORKSPACE" --json
```

The doctor checks app icon presence, entitlements, Info.plist privacy purpose strings, local metadata, screenshot state, IAP templates, and release-sensitive residue.

### `metadata`

Manage local App Store metadata.

```bash
ascendkit metadata init --workspace "$WORKSPACE" --locale en-US
```

Writes a starter metadata JSON file for one locale.

```bash
ascendkit metadata import-fastlane \
  --workspace "$WORKSPACE" \
  --source "$APP_ROOT/fastlane/metadata" \
  --json
```

Imports fastlane metadata folders into AscendKit's local metadata model.

```bash
ascendkit metadata status --workspace "$WORKSPACE" --json
```

Lists local metadata bundles known to the workspace.

```bash
ascendkit metadata lint --workspace "$WORKSPACE" --locale en-US --json
```

Checks required fields and App Store length constraints.

```bash
ascendkit metadata diff --workspace "$WORKSPACE" --json
```

Compares local metadata with observed ASC metadata saved in the workspace.

### `screenshots`

Plan, import, validate, and compose local screenshot artifacts.

```bash
ascendkit screenshots plan \
  --workspace "$WORKSPACE" \
  --screens Home,Settings,Paywall \
  --features Onboarding,Sync,Premium \
  --platforms iOS \
  --locales en-US,zh-Hans \
  --json
```

Creates a deterministic screenshot plan with coverage warnings.

```bash
ascendkit screenshots destinations --workspace "$WORKSPACE" --json
```

Discovers available local iOS simulators and recommends screenshot capture destinations for the workspace platforms.

```bash
ascendkit screenshots capture-plan \
  --workspace "$WORKSPACE" \
  --scheme MyApp \
  --configuration Debug \
  --json
```

Writes `screenshots/manifests/capture-plan.json` with deterministic `xcodebuild test` commands, locale flags, result bundle paths, and `ASCENDKIT_SCREENSHOT_OUTPUT_DIR` environment values for UI tests. If `--destination` is omitted, AscendKit recommends an available local simulator. This is a local capture plan only; it does not mutate App Store Connect.

UI tests can produce screenshots in either of two supported ways:

```swift
let screenshot = XCUIScreen.main.screenshot()

// Preferred when the test runner receives AscendKit environment values.
let outputURL = URL(fileURLWithPath: ProcessInfo.processInfo.environment["ASCENDKIT_SCREENSHOT_OUTPUT_DIR"]!)
    .appendingPathComponent("01-home.png")
try screenshot.pngRepresentation.write(to: outputURL, options: [.atomic])

// Robust fallback: AscendKit also imports ordered XCTest attachments from .xcresult.
let attachment = XCTAttachment(screenshot: screenshot)
attachment.name = "01-home.png"
attachment.lifetime = .keepAlways
add(attachment)
```

Attachment names must start with an ordered screenshot stem such as `01-home`, `02-settings`, or `03-paywall`. AscendKit ignores generic attachments such as launch screenshots to avoid importing unrelated diagnostics.

```bash
ascendkit screenshots capture --workspace "$WORKSPACE" --json
```

Executes the saved capture plan locally, writes `screenshots/manifests/capture-result.json`, stores stdout/stderr logs under `screenshots/capture/logs`, imports ordered `.xcresult` attachments when the raw output directory is empty, and refreshes the screenshot import manifest when all capture commands succeed.

```bash
ascendkit screenshots workflow run \
  --workspace "$WORKSPACE" \
  --scheme MyApp \
  --mode framedPoster \
  --copy "$WORKSPACE/screenshots/copy/en-US.json" \
  --json
```

Runs the local screenshot workflow end to end: recommends local simulator destinations, writes a fresh capture plan, executes local Xcode UI tests, refreshes the import manifest, refreshes/lints the provided copy file, composes final screenshots, and writes `screenshots/manifests/workflow-result.json`. The default workflow composition mode is `framedPoster`.

```bash
ascendkit screenshots workflow status --workspace "$WORKSPACE" --json
```

Summarizes capture plan, capture execution, import manifest, composition manifest, workflow result, and upload plan readiness in one report.

```bash
ascendkit screenshots copy init --workspace "$WORKSPACE" --locale en-US --json
ascendkit screenshots copy refresh --workspace "$WORKSPACE" --locale en-US --json
ascendkit screenshots copy lint --workspace "$WORKSPACE" --locale en-US --json
```

Generates, refreshes, and validates an editable framed-poster copy template at `screenshots/copy/en-US.json` from `screenshot-plan.json`. Use `copy refresh` after the screenshot plan changes; it preserves edited titles/subtitles for matching files and removes stale entries. Lint results are persisted to `screenshots/manifests/copy-lint.json` and included in workflow status. Edit titles and subtitles there before running `screenshots compose --mode framedPoster` or `screenshots workflow run --mode framedPoster`.

```bash
ascendkit screenshots readiness \
  --workspace "$WORKSPACE" \
  --source /path/to/screenshots \
  --json
```

Validates whether a screenshot source folder can be imported.

```bash
ascendkit screenshots import --workspace "$WORKSPACE" --source /path/to/screenshots
```

Imports screenshots from a user-provided folder into a manifest.

```bash
ascendkit screenshots import-fastlane \
  --workspace "$WORKSPACE" \
  --source "$APP_ROOT/fastlane/screenshots" \
  --locales en-US,zh-Hans
```

Imports fastlane-style screenshots.

```bash
ascendkit screenshots compose --workspace "$WORKSPACE" --mode storeReadyCopy
ascendkit screenshots compose --workspace "$WORKSPACE" --mode poster
ascendkit screenshots compose --workspace "$WORKSPACE" --mode deviceFrame
ascendkit screenshots compose --workspace "$WORKSPACE" --mode framedPoster --copy "$WORKSPACE/screenshots/copy/en-US.json"
```

Composition modes:

- `storeReadyCopy`: organize imported images for upload.
- `poster`: render local poster-style PNG artifacts.
- `deviceFrame`: render generic local framed PNG artifacts.
- `framedPoster`: render App Store-sized PNG artifacts with a background, title/subtitle copy, and an inset device frame while preserving the source screenshot dimensions.

Optional framed poster copy file:

```json
{
  "items": [
    {
      "locale": "en-US",
      "platform": "iOS",
      "fileName": "01-today.png",
      "title": "Choose Three",
      "subtitle": "Set a calm focus for today"
    }
  ]
}
```

```bash
ascendkit screenshots coverage --workspace "$WORKSPACE" --json

ascendkit screenshots upload-plan \
  --workspace "$WORKSPACE" \
  --display-type APP_IPHONE_67 \
  --json
```

Summarizes local screenshot coverage by locale, platform, and upload display type without making network requests.

Creates a dry-run App Store Connect screenshot upload plan from imported or composed artifacts. This is the native upload foundation; it does not mutate ASC yet.
The plan includes observed remote screenshot sets from `asc metadata observe` and reports a blocking finding when a matching locale/display type already has screenshots, preventing accidental duplicates.

```bash
ascendkit screenshots upload-plan \
  --workspace "$WORKSPACE" \
  --display-type APP_IPHONE_67 \
  --replace-existing \
  --json
```

Plans explicit deletion of matching remote screenshots before upload. This still does not mutate ASC; it only records `remoteScreenshotsToDelete` in the upload plan.

```bash
ascendkit screenshots upload \
  --workspace "$WORKSPACE" \
  --replace-existing \
  --confirm-remote-mutation \
  --json
```

Executes native screenshot upload through App Store Connect by optionally deleting planned remote screenshots, creating or reusing screenshot sets, reserving screenshots, uploading ASC asset parts, and committing checksums. This command mutates ASC only with `--confirm-remote-mutation`.
If `screenshots upload-plan` has findings, execution refuses to proceed.
Transient ASC and asset-upload requests are retried with bounded backoff. If one screenshot fails after execution starts, AscendKit records the failure in `failedItems` and continues with remaining screenshots when possible.
After each commit, AscendKit polls `assetDeliveryState` for a bounded number of attempts and records both the final state and `assetDeliveryPollAttempts` for each uploaded screenshot.
Use `screenshots upload-status` to summarize uploaded, failed, deleted, and retryable screenshot items without making network requests.

### `asc auth`

Configure App Store Connect credentials without storing private key contents.

```bash
ascendkit asc auth save-profile \
  --name production \
  --issuer-id ASC_ISSUER_ID \
  --key-id ASC_KEY_ID \
  --private-key-provider file \
  --private-key-ref /secure/path/AuthKey_KEYID.p8
```

Profiles are saved under `~/.ascendkit/profiles/asc/` with owner-only permissions.

```bash
ascendkit asc auth profiles --json
```

Lists saved auth profiles with redacted IDs.

```bash
ascendkit asc auth init --workspace "$WORKSPACE" --profile production
ascendkit asc auth check --workspace "$WORKSPACE" --json
```

Writes and validates the workspace auth config.

Supported secret providers:

- `file`: read a private key from a local file path.
- `env`: read a secret from an environment variable.

`keychain` references may appear in older local profiles, but new CLI auth commands only accept `file` and `env` until a fully verified Keychain resolver is added.

### `asc lookup` and `asc apps`

Plan and perform ASC app lookup.

```bash
ascendkit asc lookup plan --workspace "$WORKSPACE" --json
```

Writes the planned read-only ASC lookup shape.

```bash
ascendkit asc apps lookup --workspace "$WORKSPACE" --json
```

Uses the official ASC API to find the app from the release manifest bundle ID.

`asc lookup apps` is retained as a compatibility alias:

```bash
ascendkit asc lookup apps --workspace "$WORKSPACE" --json
```

### `asc builds`

Observe or import App Store Connect build candidates.

```bash
ascendkit asc builds observe --workspace "$WORKSPACE" --json
```

Fetches remote ASC builds for the selected app.

```bash
ascendkit asc builds list --workspace "$WORKSPACE" --json
```

Prints currently saved build candidates.

```bash
ascendkit asc builds import \
  --workspace "$WORKSPACE" \
  --id BUILD_ID \
  --version 1.0 \
  --build 7 \
  --state processed \
  --json
```

Imports a build candidate manually. This is useful for deterministic tests or when remote observation is unavailable.

### `asc metadata`

Observe, plan, and apply App Store metadata.

```bash
ascendkit asc metadata import \
  --workspace "$WORKSPACE" \
  --file /path/to/observed-state.json \
  --json
```

Imports previously observed ASC metadata state.

```bash
ascendkit asc metadata observe --workspace "$WORKSPACE" --json
```

Fetches current ASC metadata for the app/version.

```bash
ascendkit asc metadata plan --workspace "$WORKSPACE" --json
```

Builds a dry-run mutation plan from local metadata and observed ASC state.

```bash
ascendkit asc metadata requests --workspace "$WORKSPACE" --json
```

Builds grouped JSON:API request plans from the mutation plan.

```bash
ascendkit asc metadata apply \
  --workspace "$WORKSPACE" \
  --confirm-remote-mutation \
  --json

ascendkit asc metadata status --workspace "$WORKSPACE" --json
```

Applies remote metadata mutations. The confirmation flag is required by design.
Use `asc metadata status` after observe/diff/apply to summarize whether metadata is ready for review planning, including stale diff and release-notes-only cases.

### `asc pricing`

Plan or apply App Store pricing without fastlane.

```bash
ascendkit asc pricing set-free --workspace "$WORKSPACE" --json
```

Finds the free app price point for the base territory and writes `asc/pricing-result.json` without mutating remote state.

```bash
ascendkit asc pricing set-free \
  --workspace "$WORKSPACE" \
  --base-territory USA \
  --confirm-remote-mutation \
  --json
```

Creates an App Store Connect `appPriceSchedules` resource that sets the app to free. This uses the official ASC API and does not depend on fastlane.

### `asc privacy`

Record or attempt App Privacy publication state.

```bash
ascendkit asc privacy set-not-collected \
  --workspace "$WORKSPACE" \
  --confirm-remote-mutation \
  --json

ascendkit asc privacy status --workspace "$WORKSPACE" --json
```

Attempts to publish App Privacy as Data Not Collected and records the result in `asc/privacy-status.json`. The status JSON includes `readyForSubmission` and `nextActions` so agents can make the final readiness decision without parsing prose. If Apple rejects API-key auth for the App Privacy endpoint, complete App Privacy in App Store Connect UI and then record the manual handoff:

```bash
ascendkit asc privacy confirm-manual \
  --workspace "$WORKSPACE" \
  --data-not-collected \
  --json
```

### `submit`

Prepare and execute App Review submission.

```bash
ascendkit submit review-info init --workspace "$WORKSPACE"
```

Writes an editable reviewer-info template.

```bash
ascendkit submit review-info set \
  --workspace "$WORKSPACE" \
  --first-name "Ada" \
  --last-name "Lovelace" \
  --email "review@example.com" \
  --phone "+15555555555" \
  --notes "No login required." \
  --requires-login false
```

Writes reviewer contact, notes, and login requirement. If login is required, pass `--requires-login true`, `--credential-ref ENV_VAR_NAME`, and `--access-instructions "..."`. The credential reference points to an environment variable; do not place review passwords in the repository.

```bash
ascendkit submit readiness --workspace "$WORKSPACE" --json
```

Builds a checklist of release prerequisites. For `framedPoster` screenshot composition, readiness also requires a clean `screenshots/manifests/copy-lint.json` report.

```bash
ascendkit submit prepare --workspace "$WORKSPACE" --json
```

Creates a submission preparation summary.

```bash
ascendkit submit review-plan --workspace "$WORKSPACE" --json
```

Builds a review submission plan from local readiness, ASC state, metadata apply results, and selected build.

```bash
ascendkit submit handoff --workspace "$WORKSPACE"
```

Writes a human-readable review handoff Markdown file, including App Privacy state, readiness, and next actions.

```bash
ascendkit submit execute \
  --workspace "$WORKSPACE" \
  --confirm-remote-submission \
  --json
```

Records a non-executed submission result explaining that remote review submission execution is boundary-disabled. Use `submit handoff` as the supported final AscendKit step, then submit manually in App Store Connect.

### `iap`

Create and validate local subscription templates.

```bash
ascendkit iap template init --workspace "$WORKSPACE" --json
ascendkit iap validate --workspace "$WORKSPACE" --json
```

This is a local validation layer. Remote IAP creation and subscription sync are not part of the current command surface.

## Workspace Layout

AscendKit writes release state under:

```text
<app-root>/.ascendkit/releases/<release-id>/
```

Important files:

- `manifest.json`: discovered app/project metadata.
- `doctor-report.json`: release doctor results.
- `metadata/source/*.json`: local source metadata.
- `metadata/localized/*.json`: imported or localized metadata.
- `metadata/lint/*.json`: lint results.
- `screenshots/manifests/*.json`: screenshot import/composition manifests.
- `screenshots/manifests/capture-plan.json`: local Xcode UI-test screenshot capture command plan.
- `screenshots/manifests/capture-result.json`: local screenshot capture execution result with log paths and produced files.
- `screenshots/manifests/workflow-result.json`: local screenshot workflow result joining capture, import refresh, and composition.
- `screenshots/manifests/upload.json`: dry-run native ASC screenshot upload plan.
- `screenshots/manifests/upload-result.json`: native ASC screenshot upload execution result, including uploaded items, asset delivery state, delivery poll attempts, deleted remote screenshots, and per-item failures.
- `asc/auth.json`: ASC auth config with secret references only.
- `asc/apps.json`: ASC app lookup result.
- `asc/observed-state.json`: observed ASC metadata state.
- `asc/metadata-plan.json`: metadata mutation dry-run plan.
- `asc/metadata-requests.json`: JSON:API request plan.
- `asc/metadata-apply-result.json`: remote metadata apply result.
- `asc/pricing-result.json`: pricing plan or apply result.
- `build/candidates.json`: build candidates.
- `review/reviewer-info.json`: reviewer contact and access notes.
- `review/submission-plan.json`: planned review submission.
- `review/submission-result.json`: remote submission result.
- `audit/events.jsonl`: redacted audit log.

`.ascendkit/` is ignored by default because it may contain app-specific release state.

## Security Model

AscendKit's core rule is: commit configuration and references, not secrets.

- Do not commit `.p8` files.
- Do not commit `.ascendkit/` release workspaces.
- Do not store private keys, passwords, or reviewer login credentials in repository files.
- Use `asc auth save-profile` with `file` or `env` references.
- Prefer `--json` outputs for automation, but treat workspace artifacts as release-sensitive.
- Review `docs/security-model.md` before adapting AscendKit for team or CI use.

Remote mutation commands require explicit flags:

- `asc metadata apply --confirm-remote-mutation`
- `screenshots upload --confirm-remote-mutation`
- `screenshots upload --replace-existing --confirm-remote-mutation` for planned remote screenshot replacement.
- `submit execute --confirm-remote-submission` currently remains boundary-disabled and records a non-executed result.

## Maintainer Workflow

Run this before committing:

```bash
scripts/preflight-public-release.sh
```

Recommended local security scan:

```bash
rg -n --hidden --glob '!.build/**' --glob '!.swiftpm/**' \
  "(BEGIN .*PRIVATE KEY|AuthKey_|\\.p8|issuer_id|key_id|password|token|bearer)" .
```

Release checklist:

1. Keep `README.md` command examples aligned with `ascendkit --help`.
2. Run `scripts/package-release.sh` and verify the `.sha256` file before attaching release archives.
3. Add tests for new command behavior before expanding remote mutation.
4. Update `docs/v1-command-surface.md` and `docs/automation-boundaries.md` when scope changes.
5. Never commit real app release workspaces, screenshots, API keys, or reviewer credentials.
6. Run `workspace gitignore --workspace "$WORKSPACE" --fix` before sharing an app repo that uses AscendKit.
7. Use `workspace validate-handoff --workspace "$WORKSPACE" --export FILE` before asking another agent to take over.
8. Use `workspace next-steps --workspace "$WORKSPACE" --json` to give agents a command-oriented recovery plan.
9. Use `workspace export-summary --workspace "$WORKSPACE" --output FILE` when handing state to another agent instead of sharing `.ascendkit/`.
10. Prefer small, deterministic command outputs that can be consumed by scripts and agents.
11. After the GitHub Release workflow succeeds, run `scripts/update-homebrew-formula.sh` and `scripts/verify-homebrew-formula.sh --version VERSION`, then commit any formula checksum sync.
12. Before tagging any public release, complete the applicable gates in `docs/v1-release-readiness.md`, run `scripts/preflight-public-release.sh`, verify Homebrew install from the published formula, and confirm this README's Current Status, command examples, safety boundaries, release checklist, and maintainer workflow match the tagged release.
13. Run `scripts/v1-representative-app-smoke.sh --app-root PATH` against a representative app using the installed Homebrew binary.
14. Sync the dedicated Homebrew tap with `scripts/sync-homebrew-tap.sh --commit --push`, then verify `brew reinstall rushairer/ascendkit/ascendkit`.
15. Run `scripts/v1-release-readiness.sh --version VERSION --app-root PATH` as the combined final v1 gate after the GitHub Release and tap are published.

GitHub Actions:

- `.github/workflows/ci.yml` runs on `main` pushes and pull requests. It runs tests, shell syntax checks, whitespace checks, release packaging, and checksum verification.
- `.github/workflows/release.yml` runs on `v*` tags. It runs tests, builds the CLI archive, verifies the checksum, uploads the archive plus `.sha256`, generates `Formula/ascendkit.rb`, uploads the formula plus installer script, and verifies the published release assets with an installer smoke test.

Fastlane removal roadmap:

1. Keep `import-fastlane` commands only as migration helpers.
2. Harden native ASC screenshot replacement with ordering sync and deeper real-world recovery checks.
3. Formalize App Privacy declarations on official ASC API where available and explicit fallback paths where Apple exposes only private iris endpoints.
4. Keep binary upload out of scope; Xcode Cloud remains the preferred binary delivery path.

## Contributing

Issues and pull requests are welcome. Good contributions usually fit one of these categories:

- Safer ASC API abstractions.
- Better release-readiness diagnostics.
- More deterministic screenshot and metadata workflows.
- Tests around edge cases in real App Store Connect behavior.
- Documentation improvements that make release automation safer.

Please keep the project local-first and secret-safe. Features that require hidden global state, plaintext credentials, or unreviewable remote mutation should be redesigned before merging.

## Documentation

Useful design docs:

- `docs/project-charter.md`
- `docs/product-scope.md`
- `docs/security-model.md`
- `docs/automation-boundaries.md`
- `docs/v1-command-surface.md`
- `docs/release-workspace-model.md`
- `docs/asc-api-strategy.md`
- `docs/screenshot-pipeline.md`
- `docs/agent-release-playbook.md`

## License

AscendKit is released under the MIT License. See `LICENSE`.

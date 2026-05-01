# AscendKit

AscendKit is a local-first Swift toolkit for preparing App Store releases. It helps Apple platform teams organize release workspaces, inspect projects, lint App Store metadata, prepare screenshots, compare local metadata with App Store Connect, and execute a guarded review-submission workflow.

The project is designed for AI-assisted release work without handing raw secrets or mutable App Store state directly to an agent. AscendKit keeps release state in deterministic local files, stores only secret references, and requires explicit confirmation flags before remote App Store Connect mutations.

## Current Status

AscendKit is versioned from `v0.1.0` and follows [Semantic Versioning](https://semver.org/). The `0.y.z` line is usable but still evolving: each tagged release should build, test, and support the documented workflow, while minor versions may still refine command shapes before `1.0.0`.

AscendKit is an MVP. It has been used end-to-end on a real iOS app release workflow covering local screenshot preparation, metadata, pricing, reviewer information, build selection, screenshot upload, and guarded App Review submission. App Privacy publishing is currently documented as a boundary where Apple's IRIS endpoint may require App Store Connect UI or future Apple ID web-session support.

Implemented today:

- Swift Package with `AscendKitCore` and the `ascendkit` CLI.
- Durable release workspaces under `.ascendkit/releases/<release-id>`.
- Project intake and release doctor checks.
- Metadata templates, fastlane metadata import, linting, diffing, and ASC request planning.
- Screenshot planning, import manifests, fastlane screenshot import, local composition outputs, guarded ASC upload planning, and native screenshot upload execution.
- App Store Connect auth profiles using secret references.
- ASC app lookup, build lookup, metadata observation, metadata apply, and guarded review submission.
- Reviewer information, readiness checks, review handoff, and submission result persistence.
- Local IAP subscription template validation.

Out of scope for the current MVP:

- Binary upload.
- Archive/sign/export replacement.
- Xcode Cloud replacement.
- Deep MCP integration.
- Fully managed App Store Connect pricing/App Privacy abstractions for every Apple API edge case.
- Broad remote screenshot lifecycle management beyond guarded replace-existing deletion.

## Requirements

- macOS 14 or later.
- Swift 6.1 or later.
- Xcode command line tools.
- An App Store Connect API key for remote ASC operations.
- Optional: `fastlane` only if you are migrating existing metadata or screenshot folders. It is not required for the core workflow.

Build and test:

```bash
swift test
swift run ascendkit --help
swift run ascendkit --version
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
11. Submit for review with explicit confirmation.

Set a few shell variables first:

```bash
APP_ROOT=/path/to/YourApp
RELEASE_ID=appstore-1.0
WORKSPACE="$APP_ROOT/.ascendkit/releases/$RELEASE_ID"
```

Create the workspace:

```bash
swift run ascendkit intake inspect \
  --root "$APP_ROOT" \
  --release-id "$RELEASE_ID" \
  --save
```

Create metadata templates, or import existing fastlane metadata:

```bash
swift run ascendkit metadata init --workspace "$WORKSPACE" --locale en-US

swift run ascendkit metadata import-fastlane \
  --workspace "$WORKSPACE" \
  --source "$APP_ROOT/fastlane/metadata"
```

Lint metadata:

```bash
swift run ascendkit metadata status --workspace "$WORKSPACE"
swift run ascendkit metadata lint --workspace "$WORKSPACE" --locale en-US --json
```

Import screenshots from a folder or from fastlane:

```bash
swift run ascendkit screenshots import \
  --workspace "$WORKSPACE" \
  --source /path/to/screenshots

swift run ascendkit screenshots import-fastlane \
  --workspace "$WORKSPACE" \
  --source "$APP_ROOT/fastlane/screenshots" \
  --locales en-US,zh-Hans
```

Compose local screenshot artifacts:

```bash
swift run ascendkit screenshots copy init --workspace "$WORKSPACE" --locale en-US
swift run ascendkit screenshots copy refresh --workspace "$WORKSPACE" --locale en-US
swift run ascendkit screenshots copy lint --workspace "$WORKSPACE" --locale en-US
swift run ascendkit screenshots compose --workspace "$WORKSPACE" --mode storeReadyCopy
swift run ascendkit screenshots compose --workspace "$WORKSPACE" --mode deviceFrame
swift run ascendkit screenshots compose --workspace "$WORKSPACE" --mode poster
```

Run the local Xcode UI-test screenshot workflow without fastlane:

```bash
swift run ascendkit screenshots destinations --workspace "$WORKSPACE" --json
swift run ascendkit screenshots copy init --workspace "$WORKSPACE" --locale en-US --json
swift run ascendkit screenshots copy refresh --workspace "$WORKSPACE" --locale en-US --json
swift run ascendkit screenshots copy lint --workspace "$WORKSPACE" --locale en-US --json

swift run ascendkit screenshots workflow run \
  --workspace "$WORKSPACE" \
  --scheme MyApp \
  --mode framedPoster \
  --copy "$WORKSPACE/screenshots/copy/en-US.json" \
  --json

swift run ascendkit screenshots workflow status --workspace "$WORKSPACE" --json
```

Save an ASC auth profile. The profile stores only a reference to the private key file, not the key content:

```bash
swift run ascendkit asc auth save-profile \
  --name default \
  --issuer-id ASC_ISSUER_ID \
  --key-id ASC_KEY_ID \
  --private-key-provider file \
  --private-key-ref /secure/path/AuthKey_KEYID.p8
```

Attach that profile to the release workspace:

```bash
swift run ascendkit asc auth init \
  --workspace "$WORKSPACE" \
  --profile default

swift run ascendkit asc auth check --workspace "$WORKSPACE" --json
```

Observe the app and remote metadata:

```bash
swift run ascendkit asc lookup plan --workspace "$WORKSPACE" --json
swift run ascendkit asc apps lookup --workspace "$WORKSPACE" --json
swift run ascendkit asc metadata observe --workspace "$WORKSPACE" --json
```

Plan and upload screenshots. By default, the plan reads observed ASC screenshot sets and blocks execution when matching remote screenshots already exist. If you intend to replace existing screenshots, add `--replace-existing` to the plan and upload commands so AscendKit records and executes explicit screenshot deletions before uploading new assets:

```bash
swift run ascendkit screenshots upload-plan --workspace "$WORKSPACE" --json

swift run ascendkit screenshots upload-plan \
  --workspace "$WORKSPACE" \
  --replace-existing \
  --json

swift run ascendkit screenshots upload \
  --workspace "$WORKSPACE" \
  --replace-existing \
  --confirm-remote-mutation \
  --json
```

Plan and apply metadata changes:

```bash
swift run ascendkit metadata diff --workspace "$WORKSPACE" --json
swift run ascendkit asc metadata plan --workspace "$WORKSPACE" --json
swift run ascendkit asc metadata requests --workspace "$WORKSPACE" --json

swift run ascendkit asc metadata apply \
  --workspace "$WORKSPACE" \
  --confirm-remote-mutation \
  --json
```

Set the app price to free through the official App Store Connect API:

```bash
swift run ascendkit asc pricing set-free --workspace "$WORKSPACE" --json

swift run ascendkit asc pricing set-free \
  --workspace "$WORKSPACE" \
  --confirm-remote-mutation \
  --json
```

Observe builds and select a processed build:

```bash
swift run ascendkit asc builds observe --workspace "$WORKSPACE" --json
swift run ascendkit asc builds list --workspace "$WORKSPACE" --json
```

Add reviewer information. If no login is required, omit login credentials and leave `--requires-login` false:

```bash
swift run ascendkit submit review-info set \
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
swift run ascendkit doctor release --workspace "$WORKSPACE" --json
swift run ascendkit submit readiness --workspace "$WORKSPACE" --json
swift run ascendkit submit prepare --workspace "$WORKSPACE" --json
swift run ascendkit submit review-plan --workspace "$WORKSPACE" --json
swift run ascendkit submit handoff --workspace "$WORKSPACE"
```

Submit for review. This mutates App Store Connect and must be explicitly confirmed:

```bash
swift run ascendkit submit execute \
  --workspace "$WORKSPACE" \
  --confirm-remote-submission \
  --json
```

## Command Reference

All commands support `--json` where shown in `ascendkit --help`. JSON output is intended for scripts, CI, and AI-agent wrappers.

### `workspace`

Inspect existing release workspace state.

```bash
swift run ascendkit workspace status --workspace "$WORKSPACE"
swift run ascendkit workspace status --workspace "$WORKSPACE" --json
```

Shows which expected files exist, such as manifest, metadata, screenshots, ASC auth, readiness, and review artifacts.

```bash
swift run ascendkit workspace audit --workspace "$WORKSPACE"
```

Reads the workspace audit log. Sensitive values are redacted before they are written.

```bash
swift run ascendkit workspace list --root "$APP_ROOT"
```

Lists known release workspaces under an app root.

### `intake`

Create or update the release manifest from an Apple project.

```bash
swift run ascendkit intake inspect \
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
swift run ascendkit doctor release --workspace "$WORKSPACE" --json
```

The doctor checks app icon presence, entitlements, Info.plist privacy purpose strings, local metadata, screenshot state, IAP templates, and release-sensitive residue.

### `metadata`

Manage local App Store metadata.

```bash
swift run ascendkit metadata init --workspace "$WORKSPACE" --locale en-US
```

Writes a starter metadata JSON file for one locale.

```bash
swift run ascendkit metadata import-fastlane \
  --workspace "$WORKSPACE" \
  --source "$APP_ROOT/fastlane/metadata" \
  --json
```

Imports fastlane metadata folders into AscendKit's local metadata model.

```bash
swift run ascendkit metadata status --workspace "$WORKSPACE" --json
```

Lists local metadata bundles known to the workspace.

```bash
swift run ascendkit metadata lint --workspace "$WORKSPACE" --locale en-US --json
```

Checks required fields and App Store length constraints.

```bash
swift run ascendkit metadata diff --workspace "$WORKSPACE" --json
```

Compares local metadata with observed ASC metadata saved in the workspace.

### `screenshots`

Plan, import, validate, and compose local screenshot artifacts.

```bash
swift run ascendkit screenshots plan \
  --workspace "$WORKSPACE" \
  --screens Home,Settings,Paywall \
  --features Onboarding,Sync,Premium \
  --platforms iOS \
  --locales en-US,zh-Hans \
  --json
```

Creates a deterministic screenshot plan with coverage warnings.

```bash
swift run ascendkit screenshots destinations --workspace "$WORKSPACE" --json
```

Discovers available local iOS simulators and recommends screenshot capture destinations for the workspace platforms.

```bash
swift run ascendkit screenshots capture-plan \
  --workspace "$WORKSPACE" \
  --scheme MyApp \
  --configuration Debug \
  --json
```

Writes `screenshots/manifests/capture-plan.json` with deterministic `xcodebuild test` commands, locale flags, result bundle paths, and `ASCENDKIT_SCREENSHOT_OUTPUT_DIR` environment values for UI tests. If `--destination` is omitted, AscendKit recommends an available local simulator. This is a local capture plan only; it does not mutate App Store Connect.

```bash
swift run ascendkit screenshots capture --workspace "$WORKSPACE" --json
```

Executes the saved capture plan locally, writes `screenshots/manifests/capture-result.json`, stores stdout/stderr logs under `screenshots/capture/logs`, and refreshes the screenshot import manifest when all capture commands succeed.

```bash
swift run ascendkit screenshots workflow run \
  --workspace "$WORKSPACE" \
  --scheme MyApp \
  --mode framedPoster \
  --copy "$WORKSPACE/screenshots/copy/en-US.json" \
  --json
```

Runs the local screenshot workflow end to end: recommends local simulator destinations, writes a fresh capture plan, executes local Xcode UI tests, refreshes the import manifest, refreshes/lints the provided copy file, composes final screenshots, and writes `screenshots/manifests/workflow-result.json`. The default workflow composition mode is `framedPoster`.

```bash
swift run ascendkit screenshots workflow status --workspace "$WORKSPACE" --json
```

Summarizes capture plan, capture execution, import manifest, composition manifest, workflow result, and upload plan readiness in one report.

```bash
swift run ascendkit screenshots copy init --workspace "$WORKSPACE" --locale en-US --json
swift run ascendkit screenshots copy refresh --workspace "$WORKSPACE" --locale en-US --json
swift run ascendkit screenshots copy lint --workspace "$WORKSPACE" --locale en-US --json
```

Generates, refreshes, and validates an editable framed-poster copy template at `screenshots/copy/en-US.json` from `screenshot-plan.json`. Use `copy refresh` after the screenshot plan changes; it preserves edited titles/subtitles for matching files and removes stale entries. Lint results are persisted to `screenshots/manifests/copy-lint.json` and included in workflow status. Edit titles and subtitles there before running `screenshots compose --mode framedPoster` or `screenshots workflow run --mode framedPoster`.

```bash
swift run ascendkit screenshots readiness \
  --workspace "$WORKSPACE" \
  --source /path/to/screenshots \
  --json
```

Validates whether a screenshot source folder can be imported.

```bash
swift run ascendkit screenshots import --workspace "$WORKSPACE" --source /path/to/screenshots
```

Imports screenshots from a user-provided folder into a manifest.

```bash
swift run ascendkit screenshots import-fastlane \
  --workspace "$WORKSPACE" \
  --source "$APP_ROOT/fastlane/screenshots" \
  --locales en-US,zh-Hans
```

Imports fastlane-style screenshots.

```bash
swift run ascendkit screenshots compose --workspace "$WORKSPACE" --mode storeReadyCopy
swift run ascendkit screenshots compose --workspace "$WORKSPACE" --mode poster
swift run ascendkit screenshots compose --workspace "$WORKSPACE" --mode deviceFrame
swift run ascendkit screenshots compose --workspace "$WORKSPACE" --mode framedPoster --copy "$WORKSPACE/screenshots/copy/en-US.json"
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
swift run ascendkit screenshots upload-plan \
  --workspace "$WORKSPACE" \
  --display-type APP_IPHONE_67 \
  --json
```

Creates a dry-run App Store Connect screenshot upload plan from imported or composed artifacts. This is the native upload foundation; it does not mutate ASC yet.
The plan includes observed remote screenshot sets from `asc metadata observe` and reports a blocking finding when a matching locale/display type already has screenshots, preventing accidental duplicates.

```bash
swift run ascendkit screenshots upload-plan \
  --workspace "$WORKSPACE" \
  --display-type APP_IPHONE_67 \
  --replace-existing \
  --json
```

Plans explicit deletion of matching remote screenshots before upload. This still does not mutate ASC; it only records `remoteScreenshotsToDelete` in the upload plan.

```bash
swift run ascendkit screenshots upload \
  --workspace "$WORKSPACE" \
  --replace-existing \
  --confirm-remote-mutation \
  --json
```

Executes native screenshot upload through App Store Connect by optionally deleting planned remote screenshots, creating or reusing screenshot sets, reserving screenshots, uploading ASC asset parts, and committing checksums. This command mutates ASC only with `--confirm-remote-mutation`.
If `screenshots upload-plan` has findings, execution refuses to proceed.
Transient ASC and asset-upload requests are retried with bounded backoff. If one screenshot fails after execution starts, AscendKit records the failure in `failedItems` and continues with remaining screenshots when possible.
After each commit, AscendKit polls `assetDeliveryState` for a bounded number of attempts and records both the final state and `assetDeliveryPollAttempts` for each uploaded screenshot.

### `asc auth`

Configure App Store Connect credentials without storing private key contents.

```bash
swift run ascendkit asc auth save-profile \
  --name production \
  --issuer-id ASC_ISSUER_ID \
  --key-id ASC_KEY_ID \
  --private-key-provider file \
  --private-key-ref /secure/path/AuthKey_KEYID.p8
```

Profiles are saved under `~/.ascendkit/profiles/asc/` with owner-only permissions.

```bash
swift run ascendkit asc auth profiles --json
```

Lists saved auth profiles with redacted IDs.

```bash
swift run ascendkit asc auth init --workspace "$WORKSPACE" --profile production
swift run ascendkit asc auth check --workspace "$WORKSPACE" --json
```

Writes and validates the workspace auth config.

Supported secret providers:

- `file`: read a private key from a local file path.
- `env`: read a secret from an environment variable.
- `keychain`: reserved in the current CLI slice.

### `asc lookup` and `asc apps`

Plan and perform ASC app lookup.

```bash
swift run ascendkit asc lookup plan --workspace "$WORKSPACE" --json
```

Writes the planned read-only ASC lookup shape.

```bash
swift run ascendkit asc apps lookup --workspace "$WORKSPACE" --json
```

Uses the official ASC API to find the app from the release manifest bundle ID.

`asc lookup apps` is retained as a compatibility alias:

```bash
swift run ascendkit asc lookup apps --workspace "$WORKSPACE" --json
```

### `asc builds`

Observe or import App Store Connect build candidates.

```bash
swift run ascendkit asc builds observe --workspace "$WORKSPACE" --json
```

Fetches remote ASC builds for the selected app.

```bash
swift run ascendkit asc builds list --workspace "$WORKSPACE" --json
```

Prints currently saved build candidates.

```bash
swift run ascendkit asc builds import \
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
swift run ascendkit asc metadata import \
  --workspace "$WORKSPACE" \
  --file /path/to/observed-state.json \
  --json
```

Imports previously observed ASC metadata state.

```bash
swift run ascendkit asc metadata observe --workspace "$WORKSPACE" --json
```

Fetches current ASC metadata for the app/version.

```bash
swift run ascendkit asc metadata plan --workspace "$WORKSPACE" --json
```

Builds a dry-run mutation plan from local metadata and observed ASC state.

```bash
swift run ascendkit asc metadata requests --workspace "$WORKSPACE" --json
```

Builds grouped JSON:API request plans from the mutation plan.

```bash
swift run ascendkit asc metadata apply \
  --workspace "$WORKSPACE" \
  --confirm-remote-mutation \
  --json
```

Applies remote metadata mutations. The confirmation flag is required by design.

### `asc pricing`

Plan or apply App Store pricing without fastlane.

```bash
swift run ascendkit asc pricing set-free --workspace "$WORKSPACE" --json
```

Finds the free app price point for the base territory and writes `asc/pricing-result.json` without mutating remote state.

```bash
swift run ascendkit asc pricing set-free \
  --workspace "$WORKSPACE" \
  --base-territory USA \
  --confirm-remote-mutation \
  --json
```

Creates an App Store Connect `appPriceSchedules` resource that sets the app to free. This uses the official ASC API and does not depend on fastlane.

### `asc privacy`

Record or attempt App Privacy publication state.

```bash
swift run ascendkit asc privacy set-not-collected \
  --workspace "$WORKSPACE" \
  --confirm-remote-mutation \
  --json

swift run ascendkit asc privacy status --workspace "$WORKSPACE" --json
```

Attempts to publish App Privacy as Data Not Collected and records the result in `asc/privacy-status.json`. If Apple rejects API-key auth for the App Privacy endpoint, complete App Privacy in App Store Connect UI and then record the manual handoff:

```bash
swift run ascendkit asc privacy confirm-manual \
  --workspace "$WORKSPACE" \
  --data-not-collected \
  --json
```

### `submit`

Prepare and execute App Review submission.

```bash
swift run ascendkit submit review-info init --workspace "$WORKSPACE"
```

Writes an editable reviewer-info template.

```bash
swift run ascendkit submit review-info set \
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
swift run ascendkit submit readiness --workspace "$WORKSPACE" --json
```

Builds a checklist of release prerequisites. For `framedPoster` screenshot composition, readiness also requires a clean `screenshots/manifests/copy-lint.json` report.

```bash
swift run ascendkit submit prepare --workspace "$WORKSPACE" --json
```

Creates a submission preparation summary.

```bash
swift run ascendkit submit review-plan --workspace "$WORKSPACE" --json
```

Builds a review submission plan from local readiness, ASC state, metadata apply results, and selected build.

```bash
swift run ascendkit submit handoff --workspace "$WORKSPACE"
```

Writes a human-readable review handoff Markdown file.

```bash
swift run ascendkit submit execute \
  --workspace "$WORKSPACE" \
  --confirm-remote-submission \
  --json
```

Attaches the selected build, updates review details, updates safe default declarations where supported, creates or reuses a review submission, creates the submission item, and submits it. The confirmation flag is required.

### `iap`

Create and validate local subscription templates.

```bash
swift run ascendkit iap template init --workspace "$WORKSPACE" --json
swift run ascendkit iap validate --workspace "$WORKSPACE" --json
```

This is a local validation layer. Remote IAP creation and subscription sync are not part of the current MVP command surface.

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
- `submit execute --confirm-remote-submission`

## Maintainer Workflow

Run this before committing:

```bash
swift test
swift run ascendkit --help
git diff --check
```

Recommended local security scan:

```bash
rg -n --hidden --glob '!.build/**' --glob '!.swiftpm/**' \
  "(BEGIN .*PRIVATE KEY|AuthKey_|\\.p8|issuer_id|key_id|password|token|bearer)" .
```

Release checklist:

1. Keep `README.md` command examples aligned with `swift run ascendkit --help`.
2. Add tests for new command behavior before expanding remote mutation.
3. Update `docs/mvp-roadmap.md` and `docs/automation-boundaries.md` when scope changes.
4. Never commit real app release workspaces, screenshots, API keys, or reviewer credentials.
5. Prefer small, deterministic command outputs that can be consumed by scripts and agents.

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
- `docs/release-workspace-model.md`
- `docs/asc-api-strategy.md`
- `docs/mvp-roadmap.md`

## License

AscendKit is released under the MIT License. See `LICENSE`.

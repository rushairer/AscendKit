# AscendKit Agent Release Playbook

This playbook is for handing a real Apple app release to an AI coding agent that did not help build AscendKit.

Use this when a developer wants an agent to run AscendKit against an app project and drive the release from local project intake to App Store Connect handoff.

## Recommended Handoff Pattern

Use both:

- A short task prompt that tells the agent what app to release and where the release workspace should live.
- This repository playbook as the durable operating manual.

Do not rely on a long one-off prompt alone. Prompts drift, while this playbook evolves with AscendKit versions.

Do not package this as a Codex Skill yet unless your team repeatedly runs this workflow across apps. A future skill should be a thin wrapper around this playbook and the CLI, not a separate source of truth.

## Minimal Agent Prompt

Generate this prompt with the installed AscendKit CLI when possible:

```bash
APP_ROOT="<<ABSOLUTE_APP_PROJECT_ROOT>>"
RELEASE_ID="<<RELEASE_ID_FOR_THIS_APP_VERSION>>"
ASC_PROFILE="<<ASC_PROFILE_NAME_OR_ASK_ME_TO_CREATE_ONE>>"

case "$APP_ROOT $RELEASE_ID $ASC_PROFILE" in
  *'<<'*'>>'*)
    echo "Stop: replace AscendKit prompt placeholders before generating the handoff prompt." >&2
    exit 64
    ;;
esac

ascendkit agent prompt \
  --app-root "$APP_ROOT" \
  --release-id "$RELEASE_ID" \
  --asc-profile "$ASC_PROFILE" \
  --output /tmp/ascendkit-agent-prompt.txt
```

The generator is read-only and should not include secrets, screenshots, reviewer information, binaries, or raw `.ascendkit/` workspace contents in the prompt. It refuses common placeholder-style sample values; if you do not know a value, ask the user instead of guessing. If you are maintaining AscendKit from a source checkout, `scripts/create-agent-handoff-prompt.sh` remains available as a contributor convenience wrapper, but release agents should prefer `ascendkit agent prompt`.

If you need to write the prompt manually, use this shape:

```text
Use AscendKit to prepare this Apple app for App Store submission.

App project root: <<ABSOLUTE_APP_PROJECT_ROOT>>
Release id: <<RELEASE_ID_FOR_THIS_APP_VERSION>>
Release workspace: <<ABSOLUTE_APP_PROJECT_ROOT>>/.ascendkit/releases/<<RELEASE_ID_FOR_THIS_APP_VERSION>>
ASC profile: <<ASC_PROFILE_NAME_OR_ASK_ME_TO_CREATE_ONE>>

Follow <<ABSOLUTE_ASCENDKIT_CHECKOUT>>/docs/agent-release-playbook.md.

Before running commands, verify that every <<...>> placeholder has been replaced with a real value. If any placeholder remains, stop and ask the user for the missing value.
Do not commit secrets, .ascendkit workspaces, screenshots, reviewer info, or App Store Connect credentials.
Do not upload binaries. Xcode Cloud handles binary upload.
Use AscendKit confirmation flags for remote ASC mutations only after dry-run plans are clean.
If App Privacy cannot be published through the API, stop at the documented App Store Connect UI handoff.
```

## Agent Operating Rules

- Treat the app repository and the AscendKit repository as separate projects.
- Use the installed `ascendkit` binary from `PATH`; do not run from AscendKit source with `swift run` unless contributing to AscendKit itself.
- Never write app-specific values into AscendKit source code.
- Never commit `.ascendkit/`, `.p8`, reviewer contact details, private screenshots, or ASC identifiers unless the user explicitly asks and the data is safe.
- Keep binary upload out of scope.
- Use Xcode Cloud or App Store Connect for processed builds, then let AscendKit observe or import the selected build.
- Before each remote mutation, run the dry-run/plan command and inspect JSON output.
- Use explicit confirmation flags only for the intended remote mutation.

## Install AscendKit

Prefer Homebrew for normal use:

```bash
brew tap rushairer/ascendkit
brew install ascendkit
ascendkit --version
ascendkit version --json
```

Use the direct installer only when Homebrew is unavailable or when validating a specific release asset:

```bash
scripts/install-ascendkit.sh --version VERSION
```

## Standard Workflow

Set paths:

```bash
APP_ROOT=/path/to/App
RELEASE_ID=app-1.0-b1
WORKSPACE="$APP_ROOT/.ascendkit/releases/$RELEASE_ID"
```

Inspect and initialize:

```bash
ascendkit --version
ascendkit intake inspect --root "$APP_ROOT" --release-id "$RELEASE_ID" --save --json
ascendkit doctor release --workspace "$WORKSPACE" --json
```

Prepare metadata:

```bash
ascendkit metadata init --workspace "$WORKSPACE" --locale en-US --json
ascendkit metadata lint --workspace "$WORKSPACE" --locale en-US --json
```

If migrating existing fastlane data, import it as a one-time compatibility step:

```bash
ascendkit metadata import-fastlane --workspace "$WORKSPACE" --source "$APP_ROOT/fastlane/metadata" --json
ascendkit screenshots import-fastlane --workspace "$WORKSPACE" --source "$APP_ROOT/fastlane/screenshots" --locales en-US --json
```

Prepare screenshots from an existing folder:

```bash
ascendkit screenshots readiness --workspace "$WORKSPACE" --source "$WORKSPACE/screenshots/raw" --json
ascendkit screenshots import --workspace "$WORKSPACE" --source "$WORKSPACE/screenshots/raw" --json
ascendkit screenshots compose --workspace "$WORKSPACE" --mode storeReadyCopy --json
```

If the app has UI-test screenshot flows, plan native local capture without fastlane:

```bash
ascendkit screenshots doctor --workspace "$WORKSPACE" --json
ascendkit screenshots scaffold-uitests --workspace "$WORKSPACE" --json
ascendkit screenshots destinations --workspace "$WORKSPACE" --json
ascendkit screenshots copy init --workspace "$WORKSPACE" --locale en-US --json
ascendkit screenshots copy refresh --workspace "$WORKSPACE" --locale en-US --json
ascendkit screenshots copy lint --workspace "$WORKSPACE" --locale en-US --json
ascendkit screenshots workflow run \
  --workspace "$WORKSPACE" \
  --scheme APP_SCHEME \
  --mode framedPoster \
  --copy "$WORKSPACE/screenshots/copy/en-US.json" \
  --json
ascendkit screenshots workflow status --workspace "$WORKSPACE" --json
```

Use `screenshots copy init` to create the editable framed-poster title/subtitle JSON before composition. Use `screenshots copy refresh` after plan changes so existing edited titles/subtitles are preserved while stale entries are removed. Use `screenshots copy lint` to persist `screenshots/manifests/copy-lint.json` against imported artifacts. Use `screenshots workflow run` as the default local capture path when the app has UI-test screenshot flows. It recommends available local simulator destinations, writes a fresh capture plan, executes only local Xcode UI tests, imports ordered `XCTAttachment` screenshots from `.xcresult` when the raw output directory is empty, refreshes the import manifest, refreshes/lints the provided copy file, composes final screenshots, and writes `screenshots/manifests/workflow-result.json`. Name screenshot attachments with ordered stems such as `01-home.png`, `02-settings.png`, and `03-paywall.png`; generic launch or diagnostic attachments are ignored. Use `screenshots workflow status` before upload planning. Do not treat capture as App Store Connect mutation or binary upload.

Use framed screenshots when desired:

```bash
ascendkit screenshots compose \
  --workspace "$WORKSPACE" \
  --mode framedPoster \
  --copy "$WORKSPACE/screenshots/copy/en-US.json" \
  --json
```

Configure ASC auth using a secret reference, not a checked-in key:

```bash
ascendkit asc auth init --workspace "$WORKSPACE" --profile PROFILE_NAME --json
ascendkit asc auth check --workspace "$WORKSPACE" --json
```

Observe App Store Connect:

```bash
ascendkit asc lookup plan --workspace "$WORKSPACE" --json
ascendkit asc apps lookup --workspace "$WORKSPACE" --json
ascendkit asc metadata observe --workspace "$WORKSPACE" --json
ascendkit asc builds observe --workspace "$WORKSPACE" --json
```

Plan and apply metadata:

```bash
ascendkit metadata diff --workspace "$WORKSPACE" --json
ascendkit asc metadata plan --workspace "$WORKSPACE" --json
ascendkit asc metadata requests --workspace "$WORKSPACE" --json
ascendkit asc metadata apply --workspace "$WORKSPACE" --confirm-remote-mutation --json
ascendkit asc metadata observe --workspace "$WORKSPACE" --json
ascendkit metadata diff --workspace "$WORKSPACE" --json
ascendkit asc metadata status --workspace "$WORKSPACE" --json
```

Set pricing when appropriate:

```bash
ascendkit asc pricing set-free --workspace "$WORKSPACE" --json
ascendkit asc pricing set-free --workspace "$WORKSPACE" --confirm-remote-mutation --json
```

Upload screenshots:

```bash
ascendkit screenshots coverage --workspace "$WORKSPACE" --json
ascendkit screenshots upload-plan --workspace "$WORKSPACE" --display-type APP_IPHONE_67 --json
ascendkit screenshots upload --workspace "$WORKSPACE" --confirm-remote-mutation --json
ascendkit screenshots upload-status --workspace "$WORKSPACE" --json
```

If replacing existing remote screenshots, explicitly opt in:

```bash
ascendkit screenshots upload-plan --workspace "$WORKSPACE" --display-type APP_IPHONE_67 --replace-existing --json
ascendkit screenshots upload --workspace "$WORKSPACE" --replace-existing --confirm-remote-mutation --json
ascendkit screenshots upload-status --workspace "$WORKSPACE" --json
```

Handle App Privacy:

```bash
ascendkit asc privacy set-not-collected --workspace "$WORKSPACE" --confirm-remote-mutation --json
ascendkit asc privacy status --workspace "$WORKSPACE" --json
```

If Apple rejects API-key auth for App Privacy, the agent must ask the user to publish App Privacy in App Store Connect UI. After the user confirms it is published as Data Not Collected:

```bash
ascendkit asc privacy confirm-manual --workspace "$WORKSPACE" --data-not-collected --json
```

Prepare review:

```bash
ascendkit submit review-info set \
  --workspace "$WORKSPACE" \
  --first-name FIRST \
  --last-name LAST \
  --email EMAIL \
  --phone PHONE \
  --requires-login false \
  --notes "No account is required." \
  --json

ascendkit submit readiness --workspace "$WORKSPACE" --json
ascendkit submit prepare --workspace "$WORKSPACE" --json
ascendkit submit review-plan --workspace "$WORKSPACE" --json
ascendkit submit handoff --workspace "$WORKSPACE" --json
ascendkit workspace summary --workspace "$WORKSPACE" --json
ascendkit workspace hygiene --workspace "$WORKSPACE" --json
ascendkit workspace gitignore --workspace "$WORKSPACE" --fix --json
ascendkit workspace export-summary --workspace "$WORKSPACE" --output /tmp/ascendkit-summary.json --json
ascendkit workspace validate-handoff --workspace "$WORKSPACE" --export /tmp/ascendkit-summary.json --json
ascendkit workspace next-steps --workspace "$WORKSPACE" --json
```

For `framedPoster` screenshot composition, readiness requires `screenshots copy lint` to have produced a clean `screenshots/manifests/copy-lint.json`.

Before committing or publishing the app repository, run `workspace hygiene` to confirm raw release artifacts are not safe to share and `workspace gitignore --fix` to make sure `.ascendkit/` is excluded from git.

For agent handoff, share the `workspace export-summary` JSON instead of zipping or copying `.ascendkit/`. The export is intentionally status-only, includes `ascendKitVersion`, `handoffCommands`, and `safetyBoundaries`, and excludes raw release artifacts.

Use `workspace validate-handoff` as the final machine-readable handoff gate. It treats remaining release blockers as receiving-agent work, but blocks handoff on unsafe sharing conditions such as missing `.gitignore` protection or plaintext secret markers. The report includes `handoffInstructions` so the receiving agent can distinguish safe handoff state from remaining release work.

Use `workspace next-steps` after any failed readiness or handoff check. It returns priority-sorted steps with command hints and directly executable commands, so the receiving agent can act without parsing prose or replacing placeholders by hand.

Only complete final review submission when readiness and the review plan are clean. AscendKit stops at the handoff boundary; use the generated handoff and submit manually in App Store Connect.

```bash
ascendkit submit handoff --workspace "$WORKSPACE" --json
```

## What To Report Back

The agent should finish with:

- The AscendKit version used.
- The app bundle id, app version, build number, and selected ASC build.
- Which metadata locales were applied.
- Which screenshot display types were uploaded.
- Pricing result.
- App Privacy status.
- Review submission handoff status or exact remaining blockers.
- Tests or validation commands run.

## When To Turn This Into A Skill

Create a local Codex Skill only after the playbook has stabilized across multiple apps.

The skill should:

- Load this playbook.
- Ask for app root, release id, and ASC profile.
- Run deterministic AscendKit commands.
- Preserve the same safety boundaries.

The skill should not duplicate release logic or hide remote mutation confirmations.

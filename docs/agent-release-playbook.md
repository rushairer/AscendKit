# AscendKit Agent Release Playbook

This playbook is for handing a real app release to an AI coding agent that did not help build AscendKit.

Use this when a developer wants an agent to run AscendKit `v0.1.0+` against an app project and drive a release from local project intake to App Store Connect handoff.

## Recommended Handoff Pattern

Use both:

- A short task prompt that tells the agent what app to release and where the workspace lives.
- This repository playbook as the durable operating manual.

Do not rely on a long one-off prompt alone. Prompts drift, while the playbook can evolve with AscendKit versions.

Do not package this as a Codex Skill yet unless your team repeatedly runs this workflow across apps. The skill should be a thin wrapper around this playbook and the CLI, not a separate source of truth.

## Minimal Agent Prompt

```text
Use AscendKit to prepare this Apple app for App Store submission.

App project root: /path/to/App
AscendKit repo: /path/to/AscendKit
Release id: app-1.0-b1

Follow /path/to/AscendKit/docs/agent-release-playbook.md.

Do not commit secrets, .ascendkit workspaces, screenshots, reviewer info, or App Store Connect credentials.
Do not upload binaries. Xcode Cloud handles binary upload.
Use AscendKit confirmation flags for remote ASC mutations only after dry-run plans are clean.
If App Privacy cannot be published through the API, stop at the documented App Store Connect UI handoff.
```

## Agent Operating Rules

- Treat the app repository and the AscendKit repository as separate projects.
- Never write app-specific values into AscendKit source code.
- Never commit `.ascendkit/`, `.p8`, reviewer contact details, private screenshots, or ASC identifiers unless the user explicitly asks and the data is safe.
- Prefer `swift run ascendkit` from a tagged AscendKit checkout.
- Keep binary upload out of scope.
- Use Xcode Cloud or App Store Connect for processed builds, then let AscendKit observe or import the selected build.
- Before each remote mutation, run the dry-run/plan command and inspect JSON output.
- Use explicit confirmation flags only for the intended remote mutation.

## Standard Workflow

Set paths:

```bash
ASCENDKIT_ROOT=/path/to/AscendKit
APP_ROOT=/path/to/App
RELEASE_ID=app-1.0-b1
WORKSPACE="$APP_ROOT/.ascendkit/releases/$RELEASE_ID"
```

Inspect and initialize:

```bash
cd "$ASCENDKIT_ROOT"
git checkout v0.1.0
swift run ascendkit --version
swift run ascendkit intake inspect --root "$APP_ROOT" --release-id "$RELEASE_ID" --save --json
swift run ascendkit doctor release --workspace "$WORKSPACE" --json
```

Prepare metadata:

```bash
swift run ascendkit metadata init --workspace "$WORKSPACE" --locale en-US --json
swift run ascendkit metadata lint --workspace "$WORKSPACE" --locale en-US --json
```

Prepare screenshots:

```bash
swift run ascendkit screenshots readiness --workspace "$WORKSPACE" --source "$WORKSPACE/screenshots/raw" --json
swift run ascendkit screenshots import --workspace "$WORKSPACE" --source "$WORKSPACE/screenshots/raw" --json
swift run ascendkit screenshots compose --workspace "$WORKSPACE" --mode storeReadyCopy --json
```

If the app has UI-test screenshot flows, plan native local capture without fastlane:

```bash
swift run ascendkit screenshots capture-plan \
  --workspace "$WORKSPACE" \
  --scheme APP_SCHEME \
  --destination "platform=iOS Simulator,name=iPhone 17 Pro Max" \
  --json
swift run ascendkit screenshots capture --workspace "$WORKSPACE" --json
```

Use the generated `screenshots/manifests/capture-plan.json` commands as the deterministic local capture contract. `screenshots capture` executes only local Xcode UI tests, writes `screenshots/manifests/capture-result.json`, and refreshes the import manifest when successful. Do not treat capture as App Store Connect mutation or binary upload.

Use framed screenshots when desired:

```bash
swift run ascendkit screenshots compose \
  --workspace "$WORKSPACE" \
  --mode framedPoster \
  --copy "$WORKSPACE/screenshots/copy/en-US.json" \
  --json
```

Configure ASC auth using a secret reference, not a checked-in key:

```bash
swift run ascendkit asc auth init --workspace "$WORKSPACE" --profile PROFILE_NAME --json
swift run ascendkit asc auth check --workspace "$WORKSPACE" --json
```

Observe App Store Connect:

```bash
swift run ascendkit asc lookup plan --workspace "$WORKSPACE" --json
swift run ascendkit asc apps lookup --workspace "$WORKSPACE" --json
swift run ascendkit asc metadata observe --workspace "$WORKSPACE" --json
swift run ascendkit asc builds observe --workspace "$WORKSPACE" --json
```

Plan and apply metadata:

```bash
swift run ascendkit metadata diff --workspace "$WORKSPACE" --json
swift run ascendkit asc metadata plan --workspace "$WORKSPACE" --json
swift run ascendkit asc metadata requests --workspace "$WORKSPACE" --json
swift run ascendkit asc metadata apply --workspace "$WORKSPACE" --confirm-remote-mutation --json
swift run ascendkit asc metadata observe --workspace "$WORKSPACE" --json
swift run ascendkit metadata diff --workspace "$WORKSPACE" --json
```

Set pricing when appropriate:

```bash
swift run ascendkit asc pricing set-free --workspace "$WORKSPACE" --json
swift run ascendkit asc pricing set-free --workspace "$WORKSPACE" --confirm-remote-mutation --json
```

Upload screenshots:

```bash
swift run ascendkit screenshots upload-plan --workspace "$WORKSPACE" --display-type APP_IPHONE_67 --json
swift run ascendkit screenshots upload --workspace "$WORKSPACE" --confirm-remote-mutation --json
```

If replacing existing remote screenshots, explicitly opt in:

```bash
swift run ascendkit screenshots upload-plan --workspace "$WORKSPACE" --display-type APP_IPHONE_67 --replace-existing --json
swift run ascendkit screenshots upload --workspace "$WORKSPACE" --replace-existing --confirm-remote-mutation --json
```

Handle App Privacy:

```bash
swift run ascendkit asc privacy set-not-collected --workspace "$WORKSPACE" --confirm-remote-mutation --json
swift run ascendkit asc privacy status --workspace "$WORKSPACE" --json
```

If Apple rejects API-key auth for App Privacy, the agent must ask the user to publish App Privacy in App Store Connect UI. After the user confirms it is published as Data Not Collected:

```bash
swift run ascendkit asc privacy confirm-manual --workspace "$WORKSPACE" --data-not-collected --json
```

Prepare review:

```bash
swift run ascendkit submit review-info set \
  --workspace "$WORKSPACE" \
  --first-name FIRST \
  --last-name LAST \
  --email EMAIL \
  --phone PHONE \
  --requires-login false \
  --notes "No account is required." \
  --json

swift run ascendkit submit readiness --workspace "$WORKSPACE" --json
swift run ascendkit submit prepare --workspace "$WORKSPACE" --json
swift run ascendkit submit review-plan --workspace "$WORKSPACE" --json
swift run ascendkit submit handoff --workspace "$WORKSPACE" --json
```

Only submit when readiness and the review plan are clean:

```bash
swift run ascendkit submit execute --workspace "$WORKSPACE" --confirm-remote-submission --json
```

## What To Report Back

The agent should finish with:

- The AscendKit version used.
- The app bundle id, app version, build number, and selected ASC build.
- Which metadata locales were applied.
- Which screenshot display types were uploaded.
- Pricing result.
- App Privacy status.
- Review submission status or exact remaining blockers.
- Tests or validation commands run.

## When To Turn This Into A Skill

Create a local Codex Skill only after the playbook has stabilized across multiple apps.

The skill should:

- Load this playbook.
- Ask for app root, release id, and ASC profile.
- Run deterministic AscendKit commands.
- Preserve the same safety boundaries.

The skill should not duplicate release logic or hide remote mutation confirmations.

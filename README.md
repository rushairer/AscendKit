# AscendKit

AscendKit is a working project folder for an open-source, AI-assisted, security-first App Store Asset Pipeline focused on modern Apple platform release assets and App Store Connect workflows.

The repository now contains the first Swift-first implementation foundation:

- `AscendKitCore` for deterministic release workspace, intake, doctor, metadata, screenshot, ASC boundary, submission, and IAP models.
- `ascendkit` CLI for the initial command surface.
- Swift Testing coverage for the first persisted models and validators.

Build and test:

```bash
swift test
```

CLI help:

```bash
swift run ascendkit --help
```

Useful first commands:

```bash
swift run ascendkit intake inspect --root /path/to/app --save
swift run ascendkit workspace list --root /path/to/app
swift run ascendkit workspace status --workspace /path/to/app/.ascendkit/releases/<release-id>
swift run ascendkit metadata init --workspace /path/to/app/.ascendkit/releases/<release-id>
swift run ascendkit metadata lint --workspace /path/to/app/.ascendkit/releases/<release-id>
swift run ascendkit screenshots plan --workspace /path/to/app/.ascendkit/releases/<release-id> --screens Home,Settings --features Onboarding,Sync --platforms iOS --locales en-US --source /path/to/screenshots
swift run ascendkit screenshots import --workspace /path/to/app/.ascendkit/releases/<release-id> --source /path/to/screenshots
swift run ascendkit screenshots compose --workspace /path/to/app/.ascendkit/releases/<release-id> --mode storeReadyCopy
swift run ascendkit screenshots compose --workspace /path/to/app/.ascendkit/releases/<release-id> --mode poster
swift run ascendkit screenshots compose --workspace /path/to/app/.ascendkit/releases/<release-id> --mode deviceFrame
swift run ascendkit asc auth save-profile --name default --issuer-id ASC_ISSUER_ID --key-id ASC_KEY_ID --private-key-provider file --private-key-ref /secure/path/AuthKey_KEYID.p8
swift run ascendkit doctor release --workspace /path/to/app/.ascendkit/releases/<release-id> --json
swift run ascendkit asc auth init --workspace /path/to/app/.ascendkit/releases/<release-id> --profile default
swift run ascendkit asc auth check --workspace /path/to/app/.ascendkit/releases/<release-id> --json
swift run ascendkit asc lookup plan --workspace /path/to/app/.ascendkit/releases/<release-id> --json
swift run ascendkit asc builds import --workspace /path/to/app/.ascendkit/releases/<release-id> --id build-123 --version 1.0 --build 7 --state processed
swift run ascendkit asc metadata import --workspace /path/to/app/.ascendkit/releases/<release-id> --file /path/to/observed-state.json
swift run ascendkit metadata diff --workspace /path/to/app/.ascendkit/releases/<release-id> --json
swift run ascendkit submit review-info init --workspace /path/to/app/.ascendkit/releases/<release-id>
swift run ascendkit submit prepare --workspace /path/to/app/.ascendkit/releases/<release-id> --json
```

The `asc auth` commands store and validate local App Store Connect credential references only. Global profiles are written under `~/.ascendkit/profiles/asc/` with owner-only permissions and should contain references to secrets, not private key contents. The `asc metadata import` and `asc builds import` commands are local observation inputs only. They persist known App Store Connect state into the release workspace so local diff/readiness commands can run deterministically; they do not mutate remote metadata, upload binaries, or submit reviews.

The `asc lookup plan` command writes a dry-run plan for the official read-only App Store Connect lookup shape AscendKit will use later. It records planned app/build lookup endpoints and findings, but performs no network request.

Screenshot composition supports deterministic store-ready copying, a local poster PNG renderer, and a generic local device-frame PNG renderer. These modes use local image files only and write organized artifacts under the release workspace.

First-wave scope is intentionally narrow. AscendKit does not build, archive, sign, upload binaries, replace Xcode Cloud, execute remote review submission, or perform broad remote App Store Connect mutation in this foundation.

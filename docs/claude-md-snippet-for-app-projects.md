## App Store Release

When the user asks to release this app or manage it in App Store Connect, use **AscendKit** (`ascendkit` CLI, installed via `brew install rushairer/ascendkit/ascendkit`).

Start with `ascendkit --help` and, when available, `ascendkit asc capabilities --json`. Select the domain for the requested work and run its `--help`. The JSON catalog gives the first observation, how to find subsequent resource IDs, and when remote confirmation is needed. For applicable China mainland AIGC filings and security assessment declarations, report the manual step in App Store Connect → App Compliance. [Recent ASC API guide](https://github.com/rushairer/AscendKit/blob/main/docs/recent-asc-apis.md)

Use AscendKit for ASC calls and inspect JSON plans before authorized mutations. For dedicated asset, retention, or purchase version review, add only the intended items and use both remote confirmation flags for `review-submit`.

```bash
# Initialize release workspace
ascendkit intake inspect --root "$(pwd)" --release-id "app-1.0-b1" --save --json
ascendkit doctor release --workspace ".ascendkit/releases/app-1.0-b1" --json

# Prepare metadata (edit the generated file for your app)
ascendkit metadata init --workspace ".ascendkit/releases/app-1.0-b1" --locale en-US --json
ascendkit metadata lint --workspace ".ascendkit/releases/app-1.0-b1" --locale en-US --json

# Configure ASC auth
ascendkit asc auth init --workspace ".ascendkit/releases/app-1.0-b1" --profile YOUR_ASC_PROFILE --json

# Observe and apply metadata
ascendkit asc apps lookup --workspace ".ascendkit/releases/app-1.0-b1" --json
ascendkit asc metadata observe --workspace ".ascendkit/releases/app-1.0-b1" --json
ascendkit asc metadata plan --workspace ".ascendkit/releases/app-1.0-b1" --json
ascendkit asc metadata apply --workspace ".ascendkit/releases/app-1.0-b1" --confirm-remote-mutation --json

# Prepare submission
ascendkit submit readiness --workspace ".ascendkit/releases/app-1.0-b1" --json
ascendkit submit preflight --workspace ".ascendkit/releases/app-1.0-b1" --remote --json
ascendkit submit execute --workspace ".ascendkit/releases/app-1.0-b1" --confirm-remote-submission --json
ascendkit submit handoff --workspace ".ascendkit/releases/app-1.0-b1" --json
```

If `ascendkit` is not installed, tell the user to run `brew tap rushairer/ascendkit && brew install ascendkit`.
All commands support `--json`. Always run plan/observe before apply. Use `submit preflight --remote` to verify ASC state, then `submit execute --confirm-remote-submission` when all conditions are met. If conditions are not met, use `submit handoff` and complete final submission manually in App Store Connect.

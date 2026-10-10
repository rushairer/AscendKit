# Product Page Optimization: AI operating playbook

AscendKit's `asc ppo` commands let an AI agent operate App Store Connect Product Page Optimization (PPO), rather than merely recommend experiments or ask the developer to fill in ASC forms. They use Apple's public API, not browser automation or private endpoints.

## Authorization and output

- Use the installed `ascendkit` binary and an existing release workspace. Initialize ASC auth and look up the app using the normal release playbook.
- Get authorization for a bounded task, for example: create one screenshots-only experiment and its treatments, upload assets, and submit that experiment for review. Ask about actual blockers, not every CLI step.
- Keep starting, stopping, deleting, or applying treatments outside the authorized scope unless the developer explicitly includes them. `promote` changes the actual product page; never infer promotion permission from permission to create a test.
- All mutation commands produce local plans unless `--confirm-remote-mutation` is supplied. Planning does not resolve credentials or make network requests. Read commands contact ASC.
- `review-submit` additionally requires `--confirm-remote-submission`. It reads all review items and refuses empty submissions or any item that is not a PPO v2 experiment. Use a dedicated PPO submission.
- Use `--json`. Each result contains `plan`, `executed`, `responses`, `upload`, and `findings`. `responses` contains the original ASC JSON documents, including every page for list operations. For creates, take the returned ID from `responses[0].data.id`, never invent an ID.
- `executed: false` means either read-only observation or an unexecuted plan; check `plan.method`. A successful upload still needs `upload.assetDeliveryState == "COMPLETE"` before review.
- The workspace stores the latest `asc/ppo/plan.json` and `asc/ppo/result.json`, plus PPO audit events. Retain the JSON returned by each step for IDs; later commands overwrite the latest snapshots.

## End-to-end screenshots experiment

The following commands show a sequence, not an unattended shell script. Replace resource IDs with real ASC response IDs. The explicit mutation flags presume the developer has authorized the corresponding operations.

```bash
# Discover existing tests first; do not create duplicates when resuming.
ascendkit asc ppo list --workspace "$WORKSPACE" --json

# Review the local plan, then execute the same command within authorized scope.
ascendkit asc ppo create --workspace "$WORKSPACE" \
  --name "Benefits-first screenshots" --traffic-proportion 50 --json
ascendkit asc ppo create --workspace "$WORKSPACE" \
  --name "Benefits-first screenshots" --traffic-proportion 50 \
  --confirm-remote-mutation --json

# EXPERIMENT_ID = returned experiment ID.
ascendkit asc ppo treatment-create --workspace "$WORKSPACE" \
  --experiment-id "$EXPERIMENT_ID" --name "Benefits first" \
  --confirm-remote-mutation --json

# TREATMENT_ID = returned treatment ID.
ascendkit asc ppo localization-create --workspace "$WORKSPACE" \
  --treatment-id "$TREATMENT_ID" --locale en-US \
  --confirm-remote-mutation --json

# LOCALIZATION_ID = returned treatment localization ID, NOT a release localization ID.
# ASC may automatically copy the original page's approved screenshot sets and assets.
ascendkit asc ppo screenshot-sets --workspace "$WORKSPACE" \
  --localization-id "$LOCALIZATION_ID" --json

# SET_ID = existing treatment screenshot-set ID from the response. Inspect before changing.
ascendkit asc ppo screenshots --workspace "$WORKSPACE" --set-id "$SET_ID" --json

# Use the numeric prefixes of the inherited filenames, specifying EVERY screenshot.
# First save the credential-free plan; then explicitly authorize the mutation.
ascendkit asc ppo screenshot-order-by-prefix --workspace "$WORKSPACE" \
  --localization-id "$LOCALIZATION_ID" --set-id "$SET_ID" --prefixes 06,07,04,03,05,01,02 --json
ascendkit asc ppo screenshot-order-by-prefix --workspace "$WORKSPACE" \
  --localization-id "$LOCALIZATION_ID" --set-id "$SET_ID" --prefixes 06,07,04,03,05,01,02 \
  --confirm-remote-mutation --json

# Repeat for each supported locale and device family. Check the original/control
# page still has its previous order; leave unrelated display types unchanged.

# Inspect reviewRequired and state; submit only if review is required.
ascendkit asc ppo get --workspace "$WORKSPACE" --experiment-id "$EXPERIMENT_ID" --json
ascendkit asc ppo review-create --workspace "$WORKSPACE" \
  --confirm-remote-mutation --json

# REVIEW_SUBMISSION_ID = returned ID of the dedicated PPO review submission.
ascendkit asc ppo review-add --workspace "$WORKSPACE" \
  --review-submission-id "$REVIEW_SUBMISSION_ID" --experiment-id "$EXPERIMENT_ID" \
  --confirm-remote-mutation --json
ascendkit asc ppo review-items --workspace "$WORKSPACE" \
  --review-submission-id "$REVIEW_SUBMISSION_ID" --json
ascendkit asc ppo review-submit --workspace "$WORKSPACE" \
  --review-submission-id "$REVIEW_SUBMISSION_ID" \
  --confirm-remote-mutation --confirm-remote-submission --json
ascendkit asc ppo review-get --workspace "$WORKSPACE" \
  --review-submission-id "$REVIEW_SUBMISSION_ID" --json

# After ASC approval (review submission reaches its final state), inspect the
# experiment again. WAITING_FOR_REVIEW does not mean the test is running.
# Only if ASC allows starting, and only with authorization to start:
ascendkit asc ppo start --workspace "$WORKSPACE" --experiment-id "$EXPERIMENT_ID" \
  --confirm-remote-mutation --json
```

`screenshot-order-by-prefix` confirms that the set appears under the specified treatment localization, retrieves **all** remote screenshot pages, requires unique numeric filename prefixes (`01-...` or `01_...`), unique IDs and `COMPLETE` delivery states, and rejects a missing or extra prefix before PATCH. It reads the remote list again after PATCH and fails if the resulting order differs. A failed readback is not a rollback: inspect the remote set before retrying. For assets without numeric prefixes, use `screenshot-order --screenshot-ids` with the complete remote ID list and independently check the result.

Only create a new screenshot set or upload a prepared screenshot when the intended treatment genuinely adds or replaces imagery. Creation after ASC already copied approved assets can produce an unwanted duplicate. Use `screenshot-set-create --localization-id --display-type` and `screenshot-upload --set-id --file` only after verifying no suitable inherited set exists. Confirm every uploaded asset reaches `COMPLETE` before review.

Check every intended locale and device screenshot count and order before review; a localized poster alone does not guarantee a localized app surface. Keep the PPO submission separate from the app-version review submission. If the associated app version is published while the experiment is pending or running, evaluate whether the change confounds conversion results. AscendKit does not yet fetch conversion, lift, or confidence statistics; inspect App Analytics before choosing a winner.

If the workspace app lookup contains exactly one app, `list`, `create`, and `review-create` can infer its ID. Otherwise supply `--app-id`. Platforms default to `IOS`, including iPadOS. Traffic proportion must be an integer from 1 to 100. Apple remains the authority for eligibility, treatment limits, asset dimensions, review readiness, and allowed state transitions.

## Other supported operations

| Operation | Action and required flags |
| --- | --- |
| Read/update/stop/delete experiment | `get`, `update`, `stop`, `delete` with `--experiment-id`; update additionally needs `--name` or `--traffic-proportion` |
| Read treatment list | `treatments --experiment-id` |
| Update/delete treatment | `treatment-update`, `treatment-delete` with `--treatment-id`; update needs `--name` or `--icon-name` |
| Use an alternate app icon | `treatment-create --experiment-id --name --icon-name`; the icon must already be in the app binary |
| Read/delete treatment localization | `localizations --treatment-id`, `localization-delete --localization-id` |
| Read treatment screenshot sets | `screenshot-sets --localization-id` |
| Delete a screenshot | `screenshot-delete --screenshot-id` |
| Apply a selected treatment | `promote --version-id --treatment-id`; requires explicit authorization to change the product page |

All writes require `--confirm-remote-mutation` to execute. Apple may reject mutations depending on current state. AscendKit does not bypass these rules.

## Resuming and failures

Before creating a resource, list its siblings and reuse the intended resource if it already exists. Creation is not an upsert. After a timeout, error, or interrupted upload, inspect the corresponding list/read commands before retrying. A failed call can have partially changed ASC, especially during multi-step asset delivery. Metadata resource mutations are not automatically retried; screenshot delivery reuses the existing upload pipeline.

For a running test, read its state before deciding to stop or edit it. Do not automatically overwrite a live page or declare a statistical winner. This first implementation does not retrieve PPO conversion/lift/confidence reports or upload preview videos. It can apply a developer-selected treatment without pretending to decide which treatment won.

## Official API references

- [Create a v2 experiment](https://developer.apple.com/documentation/appstoreconnectapi/post-v2-appstoreversionexperiments)
- [Modify a v2 experiment](https://developer.apple.com/documentation/appstoreconnectapi/patch-v2-appstoreversionexperiments-_id_)
- [Treatment create request](https://developer.apple.com/documentation/appstoreconnectapi/appstoreversionexperimenttreatmentcreaterequest)
- [Screenshot set create request](https://developer.apple.com/documentation/appstoreconnectapi/appscreenshotsetcreaterequest)
- [Review submission item create request](https://developer.apple.com/documentation/appstoreconnectapi/reviewsubmissionitemcreaterequest)
- [Create a promotion](https://developer.apple.com/documentation/appstoreconnectapi/post-v1-appstoreversionpromotions)

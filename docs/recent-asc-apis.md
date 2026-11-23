# Recent App Store Connect APIs

## China mainland App Compliance

Apple moved compliance documentation to **App Compliance** on November 16, 2026. Apps with applicable features can declare AI-generated or synthetic content, enter approved LLM or algorithm filing information, and provide evidence and a report for features that require a security assessment. ICP filing, game and publishing permits, and medical-device declarations are also managed there. [App Store Connect release notes](https://developer.apple.com/cn/help/app-store-connect/release-notes/) · [App and compliance information](https://developer.apple.com/help/app-store-connect/reference/app-information/app-and-compliance-information/)

As of November 23, 2026, Apple's public OpenAPI 4.6.1 exposes no declaration, filing, attachment, or submission operation for those App Compliance workflows. Complete applicable declarations on the App Compliance page in App Store Connect. [Official OpenAPI specification](https://developer.apple.com/sample-code/app-store-connect/app-store-connect-openapi-specification.zip)

## Commands

Start with `ascendkit asc capabilities --json` for a task-to-command guide without credentials. Run `ascendkit asc DOMAIN --help` for actions and options. The [agent release playbook](agent-release-playbook.md#discover-asc-workflows) maps requests to starter observations and the IDs to use next. The commands are available in AscendKit v1.13.0. This coverage compares AscendKit v1.12.0 with the changes documented for Apple API 4.4 through 4.6.1 and includes related discovery, relationships, and accessibility declarations.

| Domain | Operations |
| --- | --- |
| `age-rating` | Discover App Info resources, observe the declaration and per-territory ratings, and update social media, age-restricted social media, shared location, dating and relationships, and the Korea override. |
| `accessibility` | List, read, create, update, publish, and delete accessibility declarations. |
| `asset-library` | Find the app library, discover asset specifications, upload images and videos, manage placements and their ordering, and submit eligible assets for review. Covers version, custom product page, in-app event, and PPO localizations. |
| `retention` | Manage messages, versions, localized copy, offers, prices, subscription assignments, and version review. |
| `subscriptions` | Read subscriptions and set multiseat status, markets, and app invitation mode. Read and set plan availability, discover price points, preview a price change, equalize price tiers, and schedule or delete a scheduled price. |
| `purchase-versions` | Manage IAP, subscription, and subscription group versions, their v2 localizations, applicable images, and version review. |
| `game-center-moderation` | Discover Game Center detail, observe moderated leaderboard scores and blocked players, and update their blocked state. |
| `app-performance` | Read an app's performance overview and app or build performance metrics. |
| `background-assets` | Discover background assets, including by version locale. |

Apple references for recent changes. [4.4](https://developer.apple.com/documentation/appstoreconnectapi/app-store-connect-api-4-4-release-notes) · [4.4.1](https://developer.apple.com/documentation/appstoreconnectapi/app-store-connect-api-4-4-1-release-notes) · [4.5](https://developer.apple.com/documentation/appstoreconnectapi/app-store-connect-api-4-5-release-notes) · [4.5.1](https://developer.apple.com/documentation/appstoreconnectapi/app-store-connect-api-4-5-1-release-notes) · [4.6](https://developer.apple.com/documentation/appstoreconnectapi/app-store-connect-api-4-6-release-notes) · [4.6.1](https://developer.apple.com/documentation/appstoreconnectapi/app-store-connect-api-4-6-1-release-notes)

### Workspace and confirmation

- Pass `--workspace PATH` and reuse the workspace's `asc auth` configuration. App-scoped commands with `--app-id` can use the cached `asc apps lookup` result when it contains one app.
- Reads use ASC and return all pages in `responses`. Filter or request a sparse fieldset with repeatable `--query 'NAME=VALUE'`, using the parameter names from the operation's Apple documentation. Quote query names with brackets in your shell.
- Writes produce a local plan by default without loading credentials or contacting ASC. Repeat the command with `--confirm-remote-mutation` to execute. This also applies to price previews and equalization, which use POST.
- Dedicated `review-submit` commands additionally require `--confirm-remote-submission`. They check the submission's state and all active items before executing.
- Plans and results are written under `asc/<domain>/<action>/` in the workspace, with audit events. `--json` emits the result without the text heading.
- For actions that take a request `--file`, use Apple's JSON body including its top-level `data` and, where applicable, `included`. For updates, match the resource ID supplied on the command line. Upload actions take the actual image or video in `--file`.

### Age rating and accessibility

```bash
ascendkit asc age-rating app-infos --workspace "$WORKSPACE" --json
ascendkit asc age-rating observe --workspace "$WORKSPACE" --app-info-id "$APP_INFO_ID" --json
ascendkit asc age-rating territories --workspace "$WORKSPACE" --app-info-id "$APP_INFO_ID" --json
ascendkit asc age-rating set --workspace "$WORKSPACE" --declaration-id "$DECLARATION_ID" \
  --shared-location false --dating-and-relationships true --json
ascendkit asc accessibility list --workspace "$WORKSPACE" --json
```

Use the declaration ID returned by `observe`. Set only the answers you intend to change. The two Boolean content descriptors introduced in 4.6.1 currently affect Brazil's age rating. Korea accepts `NONE`, `ALL`, `TWELVE_PLUS`, `FIFTEEN_PLUS`, and `NINETEEN_PLUS` in `--korea-age-rating-override`. [Age-rating declaration update](https://developer.apple.com/documentation/appstoreconnectapi/patch-v1-ageratingdeclarations-_id_) · [API 4.6.1 release notes](https://developer.apple.com/documentation/appstoreconnectapi/app-store-connect-api-4-6-1-release-notes)

### Asset library

```bash
ascendkit asc asset-library observe --workspace "$WORKSPACE" --json
ascendkit asc asset-library ref-data --workspace "$WORKSPACE" --json
ascendkit asc asset-library image-upload --workspace "$WORKSPACE" --library-id "$LIBRARY_ID" \
  --category APP_SCREENSHOTS_AND_PREVIEWS --file "$SCREENSHOT" --json
ascendkit asc asset-library image-get --workspace "$WORKSPACE" --image-id "$IMAGE_ID" --json
ascendkit asc asset-library placement-create --workspace "$WORKSPACE" --file placement.json --json
ascendkit asc asset-library placement-order --workspace "$WORKSPACE" --file order.json --json
```

Use `image-upload` or `video-upload` to reserve the asset, send its parts, and commit. Read the asset's state before creating placements. If the operation fails after reservation and the asset still shows `AWAITING_UPLOAD`, use the matching `*-upload-resume` action with the same file and the returned asset ID. A successful commit can still be processing.

Create a separate placement for each localization and use `version-placements`, `custom-page-placements`, `event-placements`, or `treatment-placements` to observe them. Placement type and group come from `ref-data`. Use the group for the target display, including `IPHONE_DUO` where applicable. For assets that need their own review, use `review-create`, `review-add --image-id ID` or `--video-id ID`, then `review-submit`.

Apple deprecated screenshot and preview sets and resources. The existing `screenshots` and `asc ppo` commands still use those resources. Use `asc asset-library` for apps using the new library workflow. [Migrating to the App Asset Library](https://developer.apple.com/documentation/appstoreconnectapi/migrating-to-the-app-asset-library)

### Retention and pricing

```bash
ascendkit asc retention list --workspace "$WORKSPACE" --json
ascendkit asc retention message-create --workspace "$WORKSPACE" --file message.json --json
ascendkit asc retention review-add --workspace "$WORKSPACE" \
  --review-submission-id "$REVIEW_ID" --version-id "$MESSAGE_VERSION_ID" --json
ascendkit asc subscriptions price-tiers --workspace "$WORKSPACE" --subscription-id "$SUBSCRIPTION_ID" \
  --query 'filter[territory]=USA' --json
ascendkit asc subscriptions price-change-preview --workspace "$WORKSPACE" --file proposed-price.json --json
```

For `message-create`, a request body has this shape:

```json
{
  "data": {
    "type": "retentionMessages",
    "attributes": { "referenceName": "Win back subscribers" },
    "relationships": {
      "app": { "data": { "type": "apps", "id": "YOUR_APP_ID" } }
    }
  }
}
```

Create a message, then a version and its localizations. Place an asset if the message needs one. Add that version to a dedicated review submission and observe its state after submission. Associate the message and any offers with the subscription using `subscription-message-set --message-id ID` and `subscription-offers-add --offer-ids ID,ID`. [Setting up retention messaging](https://developer.apple.com/documentation/appstoreconnectapi/setting-up-retention-messaging)

Use `price-change-preview` to see how a proposed price would affect existing subscribers and `price-create` to schedule the change. Apple provides no public API to unpreserve an existing price directly. [Volume pricing](https://developer.apple.com/documentation/appstoreconnectapi/configuring-volume-pricing-for-multi-seat-subscriptions) · [Unpreserving prices after volume pricing takes effect](https://developer.apple.com/documentation/appstoreconnectapi/removing-price-preservation-after-volume-pricing-takes-effect)

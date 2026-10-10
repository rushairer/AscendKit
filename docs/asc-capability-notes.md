# AscendKit — ASC Capability Notes

## 1. Purpose

This document is not a static promise table. It is a living engineering record for what App Store Connect workflows are officially documented, actually implemented, practically reliable, and known to have sharp edges.

## 2. Why this matters

AscendKit should not pretend to know all App Store Connect automation boundaries in advance. The safer approach is to discover capabilities through official documentation, implementation, and repeated validation against real apps.

## 3. Suggested record format

Each capability note should track:
- domain
- operation
- official docs link
- official API/resource path if applicable
- implementation status
- tested with real app? (yes/no)
- caveats
- fallback strategy
- last verified date

## 4. Suggested domains

- app lookup
- editable version context
- build discovery
- metadata read/write
- screenshot set read/write
- review info preparation
- submission-related operations
- IAP/subscription operations
- pricing/availability operations
- localization operations

## 5. Example entry template

```markdown
## Domain: build discovery
- Operation: list eligible builds for app version
- Official docs: <link>
- API/resource: <resource>
- Status: planned / partial / implemented / verified
- Real-app validation: yes/no
- Caveats:
  - ...
- Fallback:
  - ...
- Last verified: YYYY-MM-DD
```

## 6. Policy

- Do not mark an operation as reliable only because documentation exists
- Do not mark an operation as unsupported only because it has not yet been implemented
- Keep caveats explicit and dated
- Prefer tested truth over speculative completeness

## 7. Strategic constraint for MVP

AscendKit MVP should assume:
- **Xcode Cloud handles build/archive/upload concerns**
- AscendKit only needs to observe build availability and processing readiness for the target release
- binary upload automation is explicitly low priority and out of MVP scope unless strong community demand later justifies it

## 8. Immediate follow-up value

As implementation starts, this file should become one of the highest-value docs in the repo because it prevents architectural drift, API hallucination, and stale assumptions.

## 9. Marketplace search detail (Title and Search Results)

- Operation: observe, create, or update the app's Title and Search Results catalog configuration
- API/resource: `GET /v1/apps/{id}/marketplaceSearchDetail`, `POST /v1/marketplaceSearchDetails`, `PATCH /v1/marketplaceSearchDetails/{id}`
- Status: implemented in AscendKit
- Local command: `ascendkit asc marketplace-search-detail observe|set --workspace PATH [--app-id ID]`
- Mutation guard: `set` is plan-only unless `--confirm-remote-mutation` is provided
- Caveats:
  - The API stores a `catalogUrl`; it does not upload the catalog payload itself.
  - The catalog URL must be an absolute `http` or `https` URL.
  - This is an alternative-marketplace/Spotlight catalog API, not the ordinary App Store product-page title, subtitle, or keyword API. Apple currently returns `500 UNEXPECTED_ERROR` for non-marketplace apps; AscendKit reports that as an unsupported capability and does not attempt a mutation.
- Last verified: 2026-10-06

## 10. Product Page Optimization (PPO)

- Operations: read/create/update/start/stop/delete v2 experiments; create/update/delete treatments and their localizations; upload/delete/reorder treatment screenshots; prepare and submit dedicated PPO reviews; apply a selected treatment to an app version.
- API/resources: `/v2/appStoreVersionExperiments`, `/v1/appStoreVersionExperimentTreatments`, `/v1/appStoreVersionExperimentTreatmentLocalizations`, `/v1/appScreenshotSets`, `/v1/appScreenshots`, `/v1/reviewSubmissions`, `/v1/reviewSubmissionItems`, `/v1/appStoreVersionPromotions`.
- Status: implemented in the unreleased development version, with mock HTTP and CLI tests.
- Real-app validation: no. No production experiment or product page was changed during implementation.
- Local command: `ascendkit asc ppo ACTION --workspace PATH [options] --json`; see [the operating playbook](product-page-optimization.md).
- Mutation guard: local plans by default; explicit `--confirm-remote-mutation` for writes. Submitting review additionally needs `--confirm-remote-submission` and refuses non-PPO review items.
- Caveats: IOS/iPadOS product pages only; Apple validates eligibility and state transitions. Alternate icons must exist in the uploaded binary. Preview-video upload and statistical result retrieval are not implemented. Resource creation is not an upsert; observe before resuming or retrying a failed write.
- Last documentation and local-test verification: 2026-10-10.

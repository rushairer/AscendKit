# AscendKit — Product Scope and System Overview

## 1. Product thesis

AscendKit exists because the Apple release workflow has split into two distinct layers:

1. **Build and binary delivery**, now increasingly served by Xcode Cloud.
2. **Asset and release-preparation automation**, still underserved by modern, deterministic, security-conscious tooling.

AscendKit is deliberately optimized for the second layer.

## 2. Core workflow modeled as stages

### Stage 0 — Release Intake
Purpose: identify what is being released and which Apple-platform surfaces are in play.

Inputs:
- Xcode project or workspace
- target/platform selection
- bundle identifiers
- current version/build numbers
- App Store Connect app identifiers (if present)
- optional release workspace config

Outputs:
- normalized release manifest
- detected platform matrix
- target and extension inventory
- release-readiness context snapshot

### Stage 1 — Release Doctor
Purpose: detect common and critical App Store release blockers before screenshot generation and submission.

Outputs:
- structured findings with severity
- auto-fix proposals where safe
- manual confirmation requirements where risk exists
- release readiness score / category summary

### Stage 2 — Screenshot Planning
Purpose: define what screenshot sets are required and what user journeys should be shown.

Outputs:
- screenshot plan
- device matrix
- locale matrix
- screen/page coverage list
- naming strategy

### Stage 3 — Screenshot Capture
Purpose: orchestrate deterministic screenshot generation using supported Apple tooling and the app’s UI automation assets.

Outputs:
- raw screenshots grouped by locale/platform/device
- capture logs
- failure reports
- completeness summary

### Stage 4 — Screenshot Composition
Purpose: convert raw screenshots into store-ready assets.

Outputs:
- rounded-corner images
- device-framed images
- poster-style images
- preview bundles
- composition manifest

### Stage 5 — Metadata Authoring
Purpose: create and manage App Store metadata locally, starting from English.

Outputs:
- English source metadata set
- localized metadata sets
- lint reports
- human review tasks

### Stage 6 — App Store Connect Sync
Purpose: compare local desired state with ASC and reconcile release assets and metadata.

Outputs:
- diff report
- dry-run plan
- apply results
- audit log

### Stage 7 — Build Readiness
Purpose: wait for or detect the correct Xcode Cloud/ASC build and confirm submission prerequisites.

Outputs:
- eligible build selection
- version/build compatibility confirmation
- processing-state summary

### Stage 8 — Submission Readiness
Purpose: validate that non-code release information is complete.

Outputs:
- review info completeness report
- export compliance reminders
- pricing/availability reminders
- IAP readiness summary
- final pre-submit checklist

### Stage 9 — Optional review submission execution (later priority)
Purpose: leave room for future official submission execution support if strong demand and API reality justify it.

Outputs:
- submission plan or future execution result
- review submission identifiers
- status tracking references
- redacted audit record

### Stage 10 — IAP / Subscription Setup Assistance
Purpose: streamline creation and preparation of common subscription products and related review metadata.

Outputs:
- subscription product definitions
- localization placeholders
- review metadata tasks
- ASC apply plan or creation result

## 3. System boundaries

### Included
- release asset preparation
- release-readiness checks
- metadata and screenshot orchestration
- secret-safe ASC interaction
- Apple-platform specific release concerns

### Excluded
- building app binaries
- replacing Xcode Cloud CI
- arbitrary agent-only workflows with no deterministic fallback
- broad enterprise workflow and approval systems in the first versions

## 4. AI role in the system

### AI is allowed to:
- generate English-first metadata drafts
- propose localizations
- explain ASC diffs or doctor findings
- inspect screenshot plans for obvious coverage gaps
- recommend fixes based on structured findings
- help prioritize screenshot-worthy product highlights when enough structured inputs exist

### AI is not allowed to be the sole authority for:
- secret resolution
- final release state persistence
- compliance truth assertions without user confirmation
- low-level mutation logic in the deterministic pipeline

## 5. Security stance

AscendKit must assume that release assets and credentials are sensitive by default.

Security requirements:
- no plaintext secrets in versioned config
- provider-based secret references
- redacted logs by default
- structured dry-run mode
- auditable mutation history
- explicit confirmation boundaries for risky actions
- screenshot sensitivity awareness for demo/test data leaks

## 6. Recommended repository baseline

```text
AscendKit/
  README.md
  docs/
    project-charter.md
    product-scope.md
    architecture.md
    release-doctor-matrix.md
    automation-boundaries.md
    security-model.md
    metadata-localization-strategy.md
    screenshot-pipeline.md
    screenshot-intelligence.md
    screenshot-readiness-rules.md
    release-workspace-model.md
    asc-api-strategy.md
    asc-capability-notes.md
    iap-module.md
  notes/
  examples/
```

## 7. Critical design commitments

- Swift-first implementation
- Apple-official-first API strategy
- CLI-first runtime
- agent integration via adapters, not via core dependency on any one agent platform
- release workspace as durable state snapshot

## 8. Open implementation questions to carry into cross-agent review

- how much of screenshot capture should be required for v0.1 versus staged later?
- should framed screenshots be first-party rendered or template/asset-driven with pluggable renderers?
- which device-frame asset acquisition strategy is legally safest and operationally simplest?
- what is the narrowest viable set of IAP features for the first public milestone?
- which ASC endpoints and operations are stable enough to prioritize in the earliest iterations?
- should remote review submission execution remain postponed until after strong community demand and proven official-path stability?

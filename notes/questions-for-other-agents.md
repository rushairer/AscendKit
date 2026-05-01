# AscendKit — Questions for External AI Agents

Use this document when asking other AI agents or reviewers for feedback.

## Context summary
AscendKit is intended to be an open-source, Swift-first, AI-assisted, security-first App Store Asset Pipeline for Apple platforms in the Xcode Cloud era.

It focuses on:
- release readiness checks
- screenshot planning/capture/composition
- metadata authoring and localization
- App Store Connect sync
- review submission orchestration
- IAP/subscription setup assistance
- secret-safe local/CI workflows

It explicitly does **not** aim to replace Xcode Cloud build/upload flows.

## Please review these questions

1. Is the product boundary correct, or still too broad?
2. Which module should be the first public MVP?
3. Is Swift the right primary language for the core and ASC client?
4. Are the release doctor checks missing any common Apple review/upload blockers?
5. Which parts should remain deterministic-only and never delegated to AI?
6. What is the safest strategy for device-frame assets and licensing?
7. Is the IAP/subscription scope too early for v0.x, or worth including from the start?
8. Which App Store Connect workflows are most likely to have official API gaps or sharp edges?
9. Should MCP be a near-term adapter goal, or delayed until the CLI core is stable?
10. What critical security or redaction concerns are still under-specified?

## Files to review
- `docs/project-charter.md`
- `docs/product-scope.md`
- `docs/architecture.md`
- `docs/release-doctor-matrix.md`
- `docs/automation-boundaries.md`
- `docs/security-model.md`
- `docs/metadata-localization-strategy.md`
- `docs/screenshot-pipeline.md`
- `docs/asc-api-strategy.md`
- `docs/iap-module.md`

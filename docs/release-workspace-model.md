# AscendKit — Release Workspace Model

## 1. Purpose

A release should not be treated as a one-shot command. It should be treated as a recoverable, inspectable, auditable workspace that can survive long-running App Store preparation flows, delayed build processing, partial screenshot generation, and staged metadata review.

## 2. Why this model is necessary

Real App Store release workflows are not atomic:
- Xcode Cloud builds may take time to appear and finish processing
- metadata, screenshots, and reviewer notes are often prepared in separate passes
- App Store Connect remote state can drift between local edits and remote sync
- AI-assisted screenshot reasoning should be reviewable and reusable rather than ephemeral
- failed sync or partial apply operations need a local recovery point

## 3. Core design principles

- **Recoverable** — work can resume after interruption
- **Auditable** — mutations and observations are recorded
- **Stateful but redacted** — useful local state is kept without leaking secrets
- **Human-reviewable** — users can inspect the state directly in files
- **Deterministic-first** — the workspace records facts and artifacts, not only AI prose

## 4. Proposed directory structure

```text
.ascendkit/
  releases/
    <release-id>/
      manifest.json
      intake.json
      doctor-report.json
      readiness.json
      screenshot-plan.json
      screenshot-insights.json
      screenshots/
        raw/
        composed/
        manifests/
      metadata/
        source/
        localized/
        lint/
      asc/
        observed-state.json
        desired-state.json
        diff.json
        apply-history.jsonl
      build/
        candidates.json
        selected-build.json
        processing-state.json
      review/
        reviewer-notes.md
        reviewer-access.json
        checklist.json
      audit/
        events.jsonl
        redactions.json
```

## 5. Release ID generation

Recommended release ID components:
- app slug
- marketing version
- optional build number
- timestamp when necessary

Example:
- `myapp-1.2.0`
- `myapp-1.2.0-b145`
- `myapp-1.2.0-2026-04-29T2230Z`

The ID should be stable enough for resumed work, but unique enough to avoid collisions across concurrent release preparation efforts.

## 6. State categories

### 6.1 User-editable inputs
- metadata source files
- reviewer notes drafts
- optional screenshot plan overrides
- release config overrides

### 6.2 Observed remote/local state
- intake results
- ASC observed state
- build processing state
- discovered target/platform inventory

### 6.3 Derived deterministic state
- doctor reports
- lint reports
- diffs
- completeness manifests
- readiness summaries

### 6.4 AI-assisted but reviewable state
- screenshot highlight analysis
- screenshot ordering rationale
- metadata rewrite suggestions
- quality explanations tied to deterministic findings

## 7. Persistence rules

- Never store raw secrets in the workspace
- Secret references are allowed; secret values are not
- Logs should be redacted by default
- AI reasoning should be stored only when it helps resume or audit work
- Large binary assets should be organized predictably and referenced from manifests

## 8. Lifecycle

1. create workspace during intake
2. enrich with doctor findings
3. attach screenshot plans and outputs
4. store metadata drafts and lint results
5. record ASC observations and diffs
6. track build readiness state
7. persist submission-readiness outcomes
8. archive or clean up after release completion

## 9. Recovery scenarios

The workspace should support recovery from:
- interrupted screenshot capture
- partial screenshot composition
- ASC sync failure mid-apply
- delayed Xcode Cloud build processing
- user reviewing metadata over multiple sessions
- AI screenshot planning revised after visual output inspection

## 10. Cleanup and archival

Provide future commands for:
- listing release workspaces
- showing status summaries
- archiving completed workspaces
- pruning temporary artifacts while preserving audit records

## 11. Documentation implication

The release workspace model should be treated as a core project commitment, not an optional implementation detail. It is one of the clearest structural differences between AscendKit and one-shot release scripts.

# AscendKit — Implementation Architecture Draft

## 1. Top-level architecture

AscendKit should be implemented as a Swift-first system with layered responsibilities:

1. **Core library**
2. **CLI runtime**
3. **Structured tool adapters (future, low priority)**
4. **Agent workflow knowledge artifacts (future)**

The project should not begin as a standalone autonomous agent. It should begin as a deterministic Swift core and CLI.

## 2. Recommended module layout

```text
Package.swift
Sources/
  AscendKitCLI/
  AscendKitCore/
    Config/
    Secrets/
    Intake/
    Doctor/
    Capture/
    Compose/
    Metadata/
    ASC/
    Submission/
    IAP/
    Audit/
    Support/
Tests/
  AscendKitCoreTests/
  AscendKitCLITests/
```

## 3. Primary module responsibilities

### Config
- parse and validate project/release configuration
- decode YAML/JSON models
- provide defaults and migration support

### Secrets
- resolve provider-backed secrets
- support env, file reference, and macOS Keychain providers first
- redact sensitive values from logs and diagnostics

### Intake
- inspect project/workspace state
- detect platforms, targets, bundle identifiers, and versioning
- collect release context from local project and config

### Doctor
- run release-readiness checks
- classify findings by severity and fixability
- generate auto-fix plans where safe

### Capture
- orchestrate screenshot runs using Apple-supported tooling
- normalize output layout and naming
- track artifact completeness

### Compose
- apply rounded corners
- apply device frames or poster-style layouts
- maintain template configuration and output manifests

### Metadata
- manage English-first metadata source files
- lint field lengths and quality constraints
- coordinate localization generation and review state

### ASC
- authenticate with App Store Connect API
- model supported resources and operations
- diff remote state vs local desired state
- apply metadata and screenshot sync operations

### Submission
- evaluate build eligibility
- enforce submission readiness rules
- prepare review-submission artifacts and status tracking
- do not assume remote review-submission execution is part of MVP

### IAP
- model subscription templates
- validate local IAP definitions
- prepare metadata and review-related requirements

### Audit
- store redacted action logs
- keep dry-run/apply traces
- support exportable diagnostics with secret stripping

## 4. CLI principles

The CLI must be the stable public interface for both humans and automation.

Each command should support:
- machine-readable JSON output
- clear non-zero exit codes
- dry-run where meaningful
- redacted output by default
- explicit confirmation flags for mutating actions

## 5. Proposed initial command tree

```text
ascendkit intake inspect
ascendkit doctor release
ascendkit doctor secrets
ascendkit metadata init
ascendkit metadata lint
ascendkit metadata diff
ascendkit metadata sync
ascendkit screenshots plan
ascendkit screenshots capture
ascendkit screenshots compose
ascendkit asc builds list
ascendkit submit readiness
ascendkit submit prepare
ascendkit iap template init
ascendkit iap validate
```

## 6. Data model direction

Suggested first-class models:
- ReleaseManifest
- PlatformTarget
- BundleTarget
- SecretRef
- DoctorFinding
- ScreenshotPlan
- ScreenshotArtifact
- MetadataFieldSet
- LocalizationBundle
- ASCDiff
- BuildCandidate
- SubmissionChecklist
- SubscriptionTemplate
- AuditRecord

## 7. Why Swift is the right primary implementation language

Swift best matches the problem domain because AscendKit is deeply tied to:
- macOS runtime behavior
- Xcode and xcodebuild orchestration
- Apple platform metadata and project structure
- Keychain and native security integration
- App Store Connect workflows

Swift keeps the core implementation aligned with the Apple ecosystem and avoids unnecessary dependency on Ruby or other legacy release-tool ecosystems.

## 8. Agent integration strategy

Future agent integration should be layered on top of the CLI/core through:
- MCP adapters
- native tool wrappers in supported agent runtimes
- workflow skills and prompt recipes

Agent integration should never bypass secret resolution or deterministic mutation logic.

## 9. Official-guidance discipline

Every implemented operation should be traced to:
- the official Apple documentation source
- the relevant App Store Connect API resource or official submission workflow
- a documented fallback if the official path is incomplete

This mapping should become part of project docs and code comments near sensitive workflows.

## 10. Implementation order recommendation

1. Config + Secrets + Audit
2. Intake + Doctor foundation
3. Release workspace model
4. Metadata local storage + lint
5. Screenshot intelligence + screenshot readiness rules
6. Screenshot composition
7. Screenshot capture
8. ASC authentication + metadata/build lookup/diff
9. Submission readiness
10. IAP assistance
11. Optional remote review submission execution only if later justified
12. Agent adapters

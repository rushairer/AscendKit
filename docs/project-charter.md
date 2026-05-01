# AscendKit — Project Charter

## 1. One-line positioning

**AscendKit** is an open-source, AI-assisted, security-first App Store Asset Pipeline for Apple platforms, built for the Xcode Cloud era and focused on screenshots, metadata, release readiness checks, App Store Connect synchronization, Xcode Cloud build-readiness observation, review submission preparation, and IAP setup assistance.

## 2. Problem statement

Modern Apple app teams increasingly rely on Xcode Cloud for build and upload workflows, but still suffer from fragmented, fragile, or outdated tooling around:

- pre-release readiness checks
- screenshot capture orchestration
- screenshot framing and marketing composition
- multilingual App Store metadata authoring
- App Store Connect metadata and asset sync
- Xcode Cloud build-readiness observation and submission preparation
- IAP setup and review preparation
- safe handling of ASC credentials and related secrets

Existing tools often carry historical baggage, indirect dependencies, unstable device support, or poor security ergonomics for secrets and release artifacts.

## 3. Vision

Create a deterministic, auditable, Apple-official-first pipeline that helps developers prepare, manage, and submit App Store release assets without depending on legacy release automation stacks.

## 4. Product definition

AscendKit is **not** a general-purpose mobile CI/CD platform and **not** a full replacement for Xcode Cloud.

AscendKit is a focused asset and release-preparation system that:

- works with Xcode Cloud rather than replacing it
- uses Apple’s latest official APIs and guidance wherever available
- uses Swift as the primary implementation language
- keeps AI as an augmentation layer, not the execution substrate
- treats secret management and redaction as first-class concerns

## 5. Primary target users

- independent Apple-platform developers
- small iOS/macOS/watchOS/visionOS teams
- Xcode Cloud users who want better App Store asset automation
- developers frustrated with unstable screenshot / metadata tooling
- AI-native developers who want an agent-ready but deterministic release pipeline

## 6. Core principles

### 6.1 Apple-official-first
Use Apple’s latest official APIs, docs, and supported workflows first. Avoid unofficial hacks unless clearly documented as fallback behavior.

### 6.2 Deterministic core
All critical execution paths must work without AI and produce reproducible results.

### 6.3 CLI-first
The core product is a Swift CLI and library, not a chat-first agent shell.

### 6.4 Security-first
Secrets, review credentials, screenshots, and release metadata must be handled with explicit redaction and provider-based secret resolution.

### 6.5 AI-assisted, not AI-dependent
AI can draft, lint, explain, and orchestrate; fixed code must validate, persist, and execute.

### 6.6 Narrow and useful scope
Solve Apple release asset workflows deeply rather than competing with all-purpose release automation platforms.

## 7. In scope

### 7.1 Release intake and project discovery
- detect platform targets: iOS, iPadOS, watchOS, macOS, visionOS
- identify bundle IDs, targets, extensions, versioning, and Xcode Cloud linkage
- inspect App Store Connect app linkage and release prerequisites

### 7.2 Release readiness checks (doctor)
- icons and required asset completeness
- Info.plist and selected release-sensitive keys
- export compliance hints, including encryption-related checks
- privacy usage description checks
- capability / entitlement readiness
- version / build consistency checks
- placeholder and staging content checks
- review information completeness checks
- metadata readiness checks
- IAP readiness checks

### 7.3 Screenshot pipeline
- screenshot plan definition
- capture orchestration using Apple-supported tooling
- locale and device matrix support
- stable naming and artifact organization
- rounded corners
- device-frame composition for required current store device sets
- poster-style composition as a frame-free alternative

### 7.4 Metadata pipeline
- English-first metadata authoring
- local file-based metadata storage
- linting against field constraints and quality checks
- AI-assisted draft generation and rewrite
- tiered localization generation strategies

### 7.5 App Store Connect sync
- diff local metadata and remote ASC state
- sync metadata and screenshot assets
- version-aware release asset synchronization
- structured dry-run and apply modes

### 7.6 Build readiness and submission preparation
- detect eligible builds from ASC/Xcode Cloud outputs
- validate submission readiness
- prepare review submission data
- track submission-related state and prerequisites
- prefer Xcode Cloud as the long-term build/archive/upload path rather than reimplementing binary delivery

### 7.7 In-App Purchase / Subscription setup assistance
- create common subscription templates
- establish product naming and localization structure
- prepare review metadata and review screenshot requirements
- support starter subscription setups such as weekly/monthly/yearly with optional trial templates

## 8. Explicit non-goals for the first major versions

- replacing Xcode Cloud build, archive, signing, or binary upload flows
- building our own binary-upload path in early versions; if ever considered, it should be very low priority and justified by strong community demand
- acting as a general mobile CI/CD platform
- managing Android Play Store publication in v1
- becoming a generic no-code AI release agent
- storing secrets directly in repo-managed plaintext configuration
- supporting every historical Apple device frame ever released

## 9. Architecture direction

AscendKit should be structured in four layers:

1. **Core engine** — deterministic Swift modules for config, secret resolution, release checks, ASC interaction, composition, and orchestration
2. **CLI** — stable human/CI interface
3. **Structured tool adapters** — MCP or other agent/tool adapters layered on top of the core (future, low priority)
4. **Workflow knowledge layer** — skills/recipes/prompts that teach agents how to use the tool correctly

## 10. Project success criteria

AscendKit succeeds if it can:

- reliably validate release readiness for a real Apple-platform app
- generate or manage compliant screenshot asset sets
- maintain local metadata and sync it to ASC
- orchestrate review submission prep without relying on legacy fastlane-style stacks
- preserve secrets safely and redact sensitive data by default
- remain useful even when no LLM is connected

## 11. Why now

- Xcode Cloud reduces the need for legacy build/upload automation
- AI increases the value of structured, agent-ready deterministic tooling
- developers still lack a modern, Apple-native release asset pipeline
- release-prep pain remains real despite build automation improvements

## 12. Open strategic questions

- what is the best public-facing name and branding positioning?
- should initial device-frame support be bundled, user-imported, or remotely bootstrapped?
- which official ASC operations are complete enough for direct support in v0.x, and which need explicit fallback handling?
- how much of screenshot capture should ship in the first public release versus later milestones?

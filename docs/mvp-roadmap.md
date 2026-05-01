# AscendKit — MVP Roadmap

## 1. Purpose

This roadmap exists to keep AscendKit implementable, reviewable, and handoff-ready for coding agents such as Codex without letting the project expand into a vague all-in-one release automation platform.

The roadmap defines:
- what MVP must include
- what is explicitly out of scope
- what is delayed by design
- the implementation order
- the constraints future implementers must obey

## 2. Product boundary for MVP

AscendKit MVP is **not** a replacement for Xcode Cloud.

MVP assumption:
- **Xcode Cloud handles build, archive, signing, and binary upload**
- AscendKit focuses on release asset preparation, release-readiness checks, screenshot workflows, local metadata management, App Store Connect observation/synchronization where appropriate, and submission-readiness preparation

This boundary is non-negotiable for MVP.

## 3. MVP goals

The MVP should prove that AscendKit can be a modern Apple release asset pipeline by delivering a coherent, deterministic workflow across four high-value areas:

1. **Release understanding**
   - inspect a project and discover what is being released
2. **Release blocking-risk detection**
   - detect common App Store release mistakes early
3. **Screenshot-centered release asset workflow**
   - plan, validate, organize, and compose screenshot assets
4. **Metadata + readiness preparation**
   - manage local metadata, inspect relevant ASC/build state, and prepare submission readiness

## 4. MVP must-have capabilities

### 4.1 Release intake
Must support:
- project/workspace inspection
- platform/target inventory
- bundle identifier discovery
- version/build discovery
- release manifest generation
- release workspace initialization

### 4.2 Release workspace
Must support:
- durable per-release workspace creation
- persisted intake/doctor/metadata/screenshot/build/readiness state
- redacted audit-friendly local records
- resumable workflows across multiple sessions

### 4.3 Release doctor (foundation)
Must support high-value checks in deterministic form:
- asset/icon completeness checks
- Info.plist release-sensitive key checks
- encryption/export-compliance hinting with safe confirmation boundaries
- privacy usage description checks
- bundle/version/build consistency checks
- capability/entitlement readiness checks
- placeholder/staging residue checks
- review-info completeness checks
- metadata completeness checks
- screenshot-readiness related checks

MVP doctor does **not** need perfect coverage of every historical review edge case.
It **does** need strong coverage of repeated real-world blockers.

### 4.4 Screenshot intelligence (constrained MVP version)
Must support:
- structured input driven highlight analysis
- screenshot plan generation
- recommended screen ordering
- per-screen purpose notes
- obvious coverage-gap warnings

MVP screenshot intelligence should rely on structured inputs such as:
- app category
- positioning notes
- key features
- important screens
- target audience
- platform context

It must **not** depend on magical full-codebase understanding.

### 4.5 Screenshot readiness
Must support:
- validation for UI-test capture path prerequisites
- validation for user-provided screenshot import path
- coverage/blocker/warning classification
- machine-readable readiness output

### 4.6 Screenshot composition
Must support:
- rounded corners
- device-frame composition for the minimal current required/important App Store device set
- poster-style alternative output
- manifest-based output organization

MVP does **not** need universal device-frame support across historical Apple hardware.

### 4.7 Metadata local storage + lint
Must support:
- English-first local metadata storage
- localized metadata file organization
- field limit validation
- metadata quality linting
- machine-readable lint output

### 4.8 ASC minimum viable integration
Must support:
- App Store Connect authentication
- app/build lookup needed for release context
- build readiness observation for Xcode Cloud-produced builds
- metadata/screenshot remote-state observation where needed for diffing
- structured dry-run/apply planning where mutation exists

MVP should prefer **observation and diffing** over ambitious remote mutation breadth.

### 4.9 Submission readiness
Must support:
- readiness checklist generation
- reviewer-info completeness evaluation
- build/version linkage validation
- export/privacy/release checklist surfacing
- final pre-submit summary

### 4.10 CLI baseline
Must support:
- stable CLI entrypoints
- JSON output mode on key commands
- clear exit codes
- dry-run for mutating commands
- redacted output by default

## 5. Explicit non-goals for MVP

The following are out of MVP scope by design:

### 5.1 Binary delivery
- building app binaries
- archiving apps
- code signing pipelines
- uploading binaries to App Store Connect
- replacing Xcode Cloud build/upload flows

### 5.2 Overreach automation
- becoming a full mobile CI/CD platform
- generalized workflow orchestration unrelated to release assets
- trying to cover every historical Apple release workflow variant

### 5.3 Premature deep integrations
- MCP-first architecture
- deep agent-platform coupling in the core
- broad remote review-submission execution
- speculative integrations without official-path validation

### 5.4 Over-ambitious AI behavior
- claiming authoritative compliance truth without confirmation
- pretending to fully infer product strategy from raw source code alone
- using AI as the only execution layer for critical mutations

### 5.5 Broad remote IAP management
- comprehensive remote IAP creation/edit flows
- advanced pricing/offers management
- broad subscription lifecycle administration

## 6. Delayed items (low priority after MVP)

These are not forbidden forever, but they should be explicitly delayed until there is real proof of need:

- remote review submission execution
- binary upload automation outside Xcode Cloud
- broad MCP adapter work
- remote IAP creation/edit flows
- advanced pricing and offer management
- deeper source-driven screenshot intelligence
- broader device-frame coverage and asset expansion

## 7. Recommended MVP implementation order

### Phase 0 — Package and foundations
- Swift package skeleton
- core module layout
- config models
- secret reference models
- audit/logging basics
- CLI shell

### Phase 1 — Release workspace + intake
- release workspace model
- release manifest model
- project inspection
- target/platform/bundle/version discovery
- workspace initialization commands

### Phase 2 — Doctor foundation
- doctor finding model
- core deterministic checks
- severity/fixability classification
- structured report output

### Phase 3 — Metadata local system
- metadata file schema
- English-first source storage
- localization folder model
- lint rules and JSON results

### Phase 4 — Screenshot planning layer
- screenshot plan schema
- structured-input highlight model
- screenshot intelligence output
- screenshot readiness rules

### Phase 5 — Screenshot asset output
- screenshot import path
- screenshot composition engine
- rounded corners
- minimal frame support
- poster-style output
- artifact manifests

### Phase 6 — ASC minimum viable integration
- auth
- app/build lookup
- build processing observation
- remote-state observation for metadata/screenshots
- initial diff model

### Phase 7 — Submission readiness
- readiness checklist aggregation
- reviewer-info checklist support
- final summary command

### Phase 8 — Post-MVP candidates
- carefully scoped sync mutation expansion
- remote submission execution (only if justified)
- remote IAP operations (only if justified)
- MCP/tool adapters (only if justified)

## 8. Codex handoff constraints

If this roadmap is handed to Codex or any coding agent, the implementer must follow these constraints:

### 8.1 Architectural constraints
- Swift-first implementation
- deterministic core
- CLI-first public interface
- release workspace as first-class persisted state
- AI layered on top, not embedded as the only logic layer

### 8.2 Scope constraints
- do not implement binary upload
- do not replace Xcode Cloud
- do not add speculative remote submission execution into MVP
- do not turn MCP into an early core dependency
- do not widen scope to Android or generic CI/CD

### 8.3 API discipline constraints
- Apple-official-first
- no fake or assumed ASC capabilities
- unresolved API uncertainty must be recorded in capability notes, not papered over in code
- use observation-first strategy where mutation support is not yet mature

### 8.4 AI constraints
- screenshot intelligence must begin with structured inputs
- no magical “understands the whole app” claims in early implementation
- AI suggestions must remain reviewable and non-authoritative for critical facts

### 8.5 UX/CLI constraints
- key commands should provide `--json`
- mutating commands should provide dry-run where relevant
- output should be redacted by default
- state should be resumable from workspace files

## 9. Suggested MVP acceptance criteria

AscendKit MVP is successful if it can do all of the following for at least one real modern Apple app project:

1. inspect the local project and generate a release workspace
2. produce a useful deterministic doctor report with real findings
3. generate a structured screenshot plan from constrained inputs
4. validate screenshot readiness for at least one supported path
5. produce store-ready composed screenshot outputs
6. store and lint English-first metadata locally
7. inspect ASC/Xcode Cloud build state needed for release preparation
8. generate a final submission-readiness summary without requiring fastlane-style binary automation

## 10. Minimal handoff set for Codex

Before handing implementation to Codex, the recommended document set is:
- `docs/project-charter.md`
- `docs/product-scope.md`
- `docs/architecture.md`
- `docs/mvp-roadmap.md`
- `docs/automation-boundaries.md`
- `docs/release-workspace-model.md`
- `docs/screenshot-intelligence.md`
- `docs/screenshot-readiness-rules.md`
- `docs/asc-capability-notes.md`

## 11. Final rule

If a future implementation decision makes AscendKit look like a build/upload automation replacement for Xcode Cloud, the decision is probably outside MVP scope and should be rejected unless the roadmap is deliberately revised later.

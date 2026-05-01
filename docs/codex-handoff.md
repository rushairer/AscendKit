# AscendKit — Codex Handoff

> This document is the implementation handoff brief for Codex. Treat it as the operative execution boundary for the first development wave.

## 1. Mission

Build the **first implementable AscendKit foundation** as a Swift-first, deterministic, CLI-first project for Apple release asset preparation.

You are **not** being asked to build the entire product in one pass.
You are being asked to build a disciplined foundation that matches the documented MVP boundary and leaves later expansion possible without contaminating the architecture.

## 2. Product understanding

AscendKit is an open-source App Store Asset Pipeline for the Xcode Cloud era.

Its core job is to help Apple-platform developers with:
- release intake
- release-readiness checks
- screenshot planning/readiness/composition
- local metadata management and linting
- App Store Connect observation/diff support where appropriate
- submission-readiness preparation

AscendKit is **not** a replacement for Xcode Cloud.

For MVP, assume:
- Xcode Cloud handles build, archive, signing, and binary upload
- AscendKit handles release asset and readiness workflows around that path

## 3. Non-negotiable implementation constraints

### 3.1 Scope constraints
Do **not** implement any of the following in the first wave:
- binary build pipelines
- archive/sign/upload automation
- replacing Xcode Cloud
- Android support
- generic CI/CD abstractions
- MCP-first architecture
- deep agent coupling in the core
- remote review submission execution
- broad remote IAP creation/editing flows

### 3.2 Architecture constraints
The first implementation must be:
- Swift-first
- deterministic at the core
- CLI-first at the public interface
- resumable via persisted release workspace state
- redacted by default for sensitive output
- Apple-official-first where ASC behavior is involved

### 3.3 AI constraints
Do **not** build magical AI-dependent behavior into the foundation.
In MVP:
- AI may be layered in later
- critical logic must work without AI
- screenshot intelligence should be structured-input-driven, not codebase-mind-reading

### 3.4 API discipline
Do not invent undocumented App Store Connect capabilities.
If a capability is uncertain:
- model the uncertainty clearly
- prefer observation over mutation
- keep the capability notes aligned with code behavior

## 4. Source documents you must follow

Read and follow these files before changing code:
- `docs/project-charter.md`
- `docs/product-scope.md`
- `docs/architecture.md`
- `docs/mvp-roadmap.md`
- `docs/automation-boundaries.md`
- `docs/release-workspace-model.md`
- `docs/screenshot-intelligence.md`
- `docs/screenshot-readiness-rules.md`
- `docs/asc-capability-notes.md`

If code and docs conflict, prefer the docs and surface the conflict explicitly.

## 5. First-wave objective

Your first-wave objective is to create a **credible, compilable, extendable skeleton plus the highest-value deterministic foundations**.

This means the result should include:
- a Swift package structure
- core module boundaries
- CLI entrypoint shell
- config and workspace models
- release manifest/intake foundations
- doctor finding models and initial checks
- metadata local-storage foundations
- screenshot planning/readiness schemas
- placeholders or interfaces for later ASC integration where appropriate

This does **not** mean implementing the entire end-state feature set immediately.

## 6. Preferred first-wave deliverables

### 6.1 Package and module skeleton
Create or refine a Swift package with modules consistent with the architecture docs, e.g.:
- `AscendKitCLI`
- `AscendKitCore`
- subdomains for Config, Secrets, Intake, Doctor, Metadata, Screenshots, ASC, Submission, Audit, Support

Exact structure may adapt to Swift package ergonomics, but architectural separation should remain visible.

### 6.2 CLI shell
Implement a CLI shell with stable command-group placeholders for:
- intake
- doctor
- metadata
- screenshots
- asc
- submit
- iap (if only as deferred/placeholder surface)

Commands should support clean help output and leave room for `--json` modes.

### 6.3 Release workspace foundation
Implement:
- release workspace directory model
- persisted manifest/state file model
- redacted audit/log record model
- resumable state-loading behavior

### 6.4 Intake foundation
Implement deterministic project discovery primitives for:
- project/workspace paths
- targets/platforms where feasible
- bundle identifiers where feasible
- version/build discovery where feasible

It is acceptable in first wave to support a narrower real-world subset if the boundaries are explicit and tested.

### 6.5 Doctor foundation
Implement:
- finding severity model
- finding category model
- structured finding output
- initial deterministic checks with clear extension points

Prefer a small number of real checks over a large number of fake or weak checks.

### 6.6 Metadata foundation
Implement:
- local metadata file models
- English-first organization
- lint result schema
- basic field validation patterns

### 6.7 Screenshot planning/readiness foundation
Implement:
- screenshot plan schema
- structured-input schema for highlight planning
- readiness result schema
- blocker/warning classification model

### 6.8 Testing baseline
Implement:
- basic unit tests for core models
- parser/validator tests where relevant
- CLI smoke tests if practical

The first wave should leave the repository in a verifiable, buildable state.

## 7. Recommended execution order

Execute in this order unless the live codebase requires a nearby adjustment:

1. inspect repo and docs
2. establish package/module skeleton
3. implement core shared models
4. implement workspace persistence
5. implement CLI shell
6. implement intake primitives
7. implement doctor foundation
8. implement metadata foundation
9. implement screenshot schemas/readiness foundation
10. add tests
11. run verification and document gaps

## 8. Output quality bar

Your output is acceptable only if it is:
- compilable or very near compilable with clearly identified blockers
- aligned with documented scope
- not padded with speculative abstractions
- not polluted by future-only integrations
- test-backed where logic exists
- clear enough for a second pass to extend safely

## 9. Explicit anti-patterns to avoid

Avoid these failure modes:

### 9.1 Scope creep
- adding upload/submission execution because it “seems nearby”
- adding generic plugin systems too early
- broadening into cross-platform release automation

### 9.2 Fake completeness
- stubbing dozens of empty features to look comprehensive
- inventing unsupported ASC behaviors
- adding “AI” labels without deterministic substance

### 9.3 Architectural pollution
- putting CLI parsing logic deep inside core models
- making the core dependent on any agent runtime
- mixing redaction/security concerns as an afterthought

### 9.4 Weak testing discipline
- skipping tests for serializers, validators, and state models
- claiming readiness without build verification

## 10. Completion definition for first wave

The first wave is complete when all of the following are true:
- the package structure exists and is coherent
- the CLI shell exists with major command groups
- release workspace persistence exists
- intake/doctor/metadata/screenshot foundation types exist and are tested at a basic level
- the project builds, or remaining blockers are explicitly documented and narrow
- no forbidden MVP-scope violations were introduced

## 11. What to do if you hit ambiguity

When ambiguity appears:
1. prefer the narrower interpretation
2. prefer deterministic local-state-first behavior
3. prefer observation over mutation
4. record the uncertainty in code comments or docs near the relevant boundary
5. do not silently widen scope

## 12. What to report back after first wave

Report back with:
- what was implemented
- what was intentionally deferred
- what assumptions were made
- what build/test commands were run
- what remains as the best next development slice

## 13. Recommended invocation guidance

Recommended mode for Codex handoff:
- use a **medium-to-high reasoning setting**
- do **not** use the absolute maximum exploration mode unless the implementation immediately hits architectural contradictions or ASC API uncertainty that truly requires deep research

Practical recommendation:
- **default: medium-high / balanced deep work** for first-wave implementation
- **increase to high** for tricky refactors, Swift package architecture disputes, or ASC capability-boundary questions
- **avoid low** because low-effort execution is more likely to drift, over-assume, or produce shallow scaffolding

## 14. Final instruction

If a proposed implementation step makes AscendKit look like a fastlane replacement for build/upload automation, stop and reject that step as outside the intended MVP boundary.

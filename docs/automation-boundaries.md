# AscendKit — Automation Boundaries

This document defines what AscendKit should detect, suggest, automatically fix, or require explicit user confirmation for.

## 1. Why this exists

The project must not blur the line between:
- deterministic validation
- safe local mutation
- sensitive compliance declarations
- remote App Store Connect mutations
- final review submission

AI assistance makes these lines even more important.

---

## 2. Action classes

### Class A — detect only
Tool inspects and reports. No mutation.

### Class B — suggest and prepare
Tool prepares a change proposal or patch plan but does not apply it automatically.

### Class C — auto-fix safe local state
Tool may automatically apply a deterministic local change with clear audit logging.

### Class D — remote mutation with explicit confirmation
Tool may mutate ASC or other remote systems only after user confirmation or explicit non-interactive confirmation flags.

### Class E — high-risk declaration or submission boundary
Tool must require explicit user confirmation and cannot hide the significance of the action.

---

## 3. Recommended boundaries by workflow

## 3.1 Release intake
- inspect targets/platforms: Class A
- generate normalized release manifest: Class B or C depending on whether it is saved locally

## 3.2 Doctor checks
- run checks and emit findings: Class A
- generate fix plan: Class B
- autofix low-risk formatting/config defaults: Class C where safe

## 3.3 Info.plist adjustments
- add clearly safe missing keys with deterministic value and strong confidence: Class C
- encryption-related keys or any compliance-sensitive declaration: Class B or E depending on confidence
- capability-related plist mutations: Class B/C with confirmation depending on blast radius

## 3.4 Screenshot planning
- generate screenshot plan proposal: Class B
- save local screenshot plan file: Class C

## 3.5 Screenshot capture
- run local deterministic capture pipeline: Class C
- retry failed simulator/test orchestration: Class C
- alter user UI test source automatically: Class B unless explicitly requested

## 3.6 Screenshot composition
- rounded corners and composition generation from existing raw assets: Class C
- replacing previously curated store-ready assets: Class D if remote sync would be impacted automatically

## 3.7 Metadata authoring
- AI draft English metadata: Class B
- AI generate localizations: Class B
- save metadata drafts locally: Class C
- auto-approve AI-generated metadata for submission: not allowed without user review step

## 3.8 ASC sync
- compute diff: Class A
- produce apply plan: Class B
- sync metadata/screenshots to ASC: Class D
- delete or replace remote assets: Class D with especially clear confirmation
- set pricing/availability through official ASC APIs: Class D
- use private App Store Connect iris endpoints: Class D with explicit caveat when no official API is available

## 3.9 Build readiness
- inspect ASC build state: Class A
- choose default eligible build candidate locally: Class B/C
- bind that build to release submission context remotely: Class D

## 3.10 Review submission
- evaluate readiness: Class A
- prepare submission payload/plan: Class B
- actually submit for review: Class E

## 3.11 IAP / subscriptions
- scaffold local subscription template: Class C
- create remote IAP products in ASC: Class D
- create/modify offers or review-facing commerce settings: Class D/E depending on risk

## 3.12 Secrets
- validate secret references: Class A
- rewrite configs to convert plaintext -> secret refs: Class B/C depending on exact operation and confidence
- reveal secret values to agent/model output: never allowed

---

## 4. AI-specific boundaries

### AI may:
- draft content
- classify findings
- explain official requirements
- propose fix plans
- suggest metadata tiers and localization packs
- highlight suspicious screenshot content or release gaps

### AI may not be sole authority for:
- compliance truth statements
- review submission decisions
- plaintext secret handling
- remote destructive changes
- irreversible asset replacement without explicit confirmation

---

## 5. Confirmation design recommendations

For every Class D/E action, AscendKit should support:
- dry-run output
- machine-readable apply plan
- redacted summary for human review
- explicit confirmation flag such as `--confirm` or `--yes --acknowledge-risk=<token>`
- clear audit log entry

Examples of actions that should never feel implicit:
- uploading metadata to ASC
- replacing screenshot sets remotely
- changing pricing or availability
- creating IAP products in ASC
- submitting the app for review
- changing compliance-related declarations based on uncertain detection

---

## 6. Recommended UI/CLI semantics

Examples:

```bash
ascendkit doctor release --json
ascendkit doctor release --autofix-safe
ascendkit asc metadata plan --workspace "$WORKSPACE" --json
ascendkit asc metadata apply --workspace "$WORKSPACE" --confirm-remote-mutation --json
ascendkit submit plan --workspace "$WORKSPACE" --json
ascendkit submit handoff --workspace "$WORKSPACE" --output review-handoff.md
```

This keeps the system deterministic and agent-friendly while preserving safe human control.

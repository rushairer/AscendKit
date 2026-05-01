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

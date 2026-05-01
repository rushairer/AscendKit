# AscendKit — App Store Connect API Strategy

## 1. Principle

AscendKit must use Apple’s latest official guidance and supported APIs whenever possible.

This means:
- App Store Connect API first for metadata/resource operations where supported
- official Apple tooling and documented workflows first for local project/build interactions
- clear documentation of any gaps, fallbacks, or manual steps

## 2. Core operational domains

Recommended early domains for official ASC coverage:
- app discovery / app context lookup
- editable app store version discovery
- metadata localizations
- screenshot set and screenshot asset management
- build lookup / build eligibility inspection
- review submission readiness data where officially supported
- subscription/IAP resource coverage as feasible in phases

## 3. Authentication direction

- JWT-based App Store Connect API auth
- secret-provider-backed `.p8` handling
- no plaintext private key storage inside repo config

## 4. Implementation discipline

Every major ASC workflow should record:
- the official resource(s) involved
- request/response mapping in code
- version/edit state assumptions
- known unsupported or ambiguous cases
- whether operation is read-only or mutating

## 5. Gaps and fallback policy

If Apple’s official interfaces do not fully cover a desired workflow:
1. document the gap explicitly
2. prefer manual confirmation and graceful degradation
3. avoid pretending unsupported automation is official
4. isolate fallback behavior clearly from the official path

## 6. Cross-agent review questions

- which ASC resource groups should be in the first client surface?
- which operations are stable enough to promise in v0.1?
- where are the likely documentation-vs-reality mismatches to expect?

# AscendKit — Release Doctor Check Matrix

This document turns repeated App Store release pain points into a structured release-readiness matrix.

## Severity scale
- **blocker** — likely to block upload, review, or listing readiness
- **high** — likely to cause rejection, serious delay, or broken listing quality
- **medium** — likely to degrade release quality or create manual churn
- **low** — useful warning, cleanup, or consistency issue

## Fixability classes
- **auto-fix** — safe deterministic change can be proposed/applied
- **guided-fix** — tool can prepare the fix but user confirmation is required
- **manual** — tool can only detect, explain, and link context

---

## 1. Project and target discovery

### 1.1 Platform inventory
- detect iOS / iPadOS / watchOS / macOS / visionOS targets
- identify companion apps, extensions, widgets, intents, watch targets
- severity: medium
- fixability: manual

### 1.2 Bundle identity consistency
- compare local bundle IDs and expected ASC app records
- detect mismatched targets or accidental dev bundle identifiers
- severity: blocker
- fixability: guided-fix

### 1.3 Versioning consistency
- inspect MARKETING_VERSION
- inspect CURRENT_PROJECT_VERSION
- compare with intended release version/build policy
- severity: high
- fixability: guided-fix

---

## 2. Icons and asset catalog readiness

### 2.1 App icon completeness
- ensure required icon slots exist for target platforms
- verify marketing icon presence where needed
- severity: blocker
- fixability: guided-fix

### 2.2 Platform-specific icon readiness
- watch icons
- macOS app icon sets
- visionOS-specific app icon requirements if applicable
- severity: blocker
- fixability: guided-fix

### 2.3 Placeholder or broken visual assets
- detect placeholder icons, temporary artwork, invalid sizes, or suspiciously empty assets
- severity: high
- fixability: manual

---

## 3. Info.plist and release-sensitive keys

### 3.1 Encryption/export compliance hinting
- inspect presence of `ITSAppUsesNonExemptEncryption`
- inspect app dependencies and capabilities for obvious signals of custom or regulated encryption usage
- propose default key insertion only when confidence is high and risk is low
- severity: high
- fixability: guided-fix

### 3.2 Usage description keys
- detect required privacy usage strings based on linked frameworks, entitlements, or known platform capabilities
- examples include camera, microphone, photo library, motion, location, Bluetooth, contacts, calendars, reminders
- severity: blocker
- fixability: guided-fix

### 3.3 Empty or placeholder usage descriptions
- detect blank, generic, or placeholder privacy purpose strings
- severity: high
- fixability: guided-fix

### 3.4 Display naming keys
- inspect app display name / bundle display name consistency
- severity: medium
- fixability: auto-fix or guided-fix depending on change scope

---

## 4. Entitlements and capabilities

### 4.1 Capability alignment
- inspect push notifications, Sign in with Apple, iCloud, associated domains, app groups, wallet, health, background modes, etc.
- compare local entitlements and known release intent
- severity: high
- fixability: manual

### 4.2 Extension capability completeness
- widgets, intents, watch companions, share extensions, notification extensions
- severity: high
- fixability: manual

---

## 5. Privacy, tracking, and policy readiness

### 5.1 App Privacy declaration readiness hints
- detect third-party SDK categories and likely data collection domains
- prompt user to confirm privacy nutrition label updates
- severity: high
- fixability: manual

### 5.2 Tracking / ATT readiness
- detect tracking-related APIs, ATT usage description, ad/analytics SDK indicators
- severity: high
- fixability: manual

### 5.3 Sign in with Apple compliance hints
- if third-party login exists, remind user to verify Sign in with Apple requirements
- severity: high
- fixability: manual

---

## 6. Review information readiness

### 6.1 Reviewer contact information
- verify review contact name, email, and phone are present
- severity: blocker
- fixability: guided-fix

### 6.2 Demo account and reviewer access steps
- detect when app likely requires login but reviewer instructions are absent
- severity: blocker
- fixability: guided-fix

### 6.3 Support / privacy / marketing URLs
- ensure URLs are present where required or strongly recommended
- severity: high
- fixability: guided-fix

### 6.4 Notes for reviewer completeness
- remind user to explain paywall, hardware dependencies, regional limitations, or special flows
- severity: medium
- fixability: manual

---

## 7. Metadata readiness

### 7.1 Required metadata presence
- app name
- subtitle
- keywords
- description
- promotional text where used
- what’s new / release notes
- severity: blocker/high depending on field
- fixability: guided-fix

### 7.2 Metadata field limits and formatting
- length limits
- keyword formatting
- repetition and low-quality phrasing
- severity: medium
- fixability: auto-fix/guided-fix

### 7.3 Placeholder or staging metadata
- detect TODO, lorem ipsum, test strings, or internal-only notes
- severity: high
- fixability: guided-fix

### 7.4 Localization completeness
- ensure configured locale tiers are complete enough for chosen release mode
- severity: medium
- fixability: guided-fix

---

## 8. Screenshot readiness

### 8.1 Screenshot plan completeness
- verify required screens, locales, and target device classes are mapped
- severity: high
- fixability: guided-fix

### 8.2 Screenshot artifact completeness
- required counts
- expected naming
- missing files
- severity: blocker
- fixability: guided-fix

### 8.3 Screenshot quality and leakage hints
- detect obvious test data, placeholder content, staging URLs, or debugging UI overlays
- severity: high
- fixability: manual

### 8.4 Composition compatibility
- ensure frame templates exist for required device classes if framed mode is selected
- severity: medium
- fixability: guided-fix

---

## 9. Build and App Store Connect linkage

### 9.1 App Store Connect app linkage
- verify app exists or is linked as expected
- severity: blocker
- fixability: manual/guided-fix

### 9.2 Build availability and processing state
- check that intended build exists and is processable for submission
- severity: blocker
- fixability: manual

### 9.3 Version/build mapping to editable release
- ensure metadata and screenshot sync target the correct editable version context
- severity: blocker
- fixability: guided-fix

---

## 10. IAP / subscription readiness

### 10.1 Subscription group existence
- verify required subscription group setup
- severity: blocker
- fixability: guided-fix

### 10.2 Product identifier policy
- validate naming structure and stability
- severity: high
- fixability: guided-fix

### 10.3 IAP localization and review metadata
- product display name / description localizations
- review screenshot / notes if required
- severity: high
- fixability: guided-fix

### 10.4 Trial / introductory offer sanity
- verify configured template matches intended pricing/offer model
- severity: medium
- fixability: guided-fix

### 10.5 Restore purchases and paywall review expectations
- remind user to verify restore flow and subscription transparency
- severity: high
- fixability: manual

---

## 11. Placeholder, staging, and debug residue

### 11.1 Test endpoints and staging domains
- search for common staging URL patterns and release-unsafe endpoints
- severity: high
- fixability: manual

### 11.2 Demo/test credentials leakage
- detect hardcoded obvious sample credentials in release-facing resources/config
- severity: high
- fixability: manual

### 11.3 Visible debug UI residue
- feature flags, test banners, logging overlays, QA toggles
- severity: high
- fixability: manual

---

## 12. Security and secrets hygiene

### 12.1 Secret storage policy
- ensure project config stores only secret references, not plaintext credentials
- severity: blocker
- fixability: guided-fix

### 12.2 Redaction safety checks
- validate that generated logs, manifests, and exported debug bundles are redacted
- severity: high
- fixability: guided-fix

### 12.3 Sensitive screenshot content hints
- detect likely personal data or unsafe review/demo data leakage in screenshots
- severity: high
- fixability: manual

---

## 13. Output contract recommendation

Every doctor run should emit structured findings with:
- unique rule ID
- title
- severity
- affected platform/target
- evidence
- fixability
- suggested remediation
- whether user confirmation is required
- whether ASC or local project state is impacted

Example shape:

```json
{
  "rule_id": "plist.encryption.missing-key",
  "severity": "high",
  "fixability": "guided-fix",
  "requires_confirmation": true,
  "summary": "ITSAppUsesNonExemptEncryption is missing.",
  "evidence": {
    "target": "MyApp",
    "plist_path": "MyApp/Info.plist"
  },
  "suggested_action": "Insert the key only after confirming the app does not implement custom regulated encryption."
}
```

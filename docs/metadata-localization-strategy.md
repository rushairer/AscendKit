# AscendKit — Metadata and Localization Strategy

## 1. English-first source strategy

AscendKit should treat English as the canonical source language for first-pass metadata generation, review, and version control.

Rationale:
- simplest review baseline
- better fit for app positioning iteration
- easier downstream localization workflow

## 2. Metadata fields to model

At minimum:
- app name
- subtitle
- keywords
- promotional text
- description
- what’s new / release notes
- support URL
- marketing URL
- privacy policy URL

Potential extension fields:
- IAP display names/descriptions
- subscription group display copy
- region-specific marketing variants

## 3. Local storage model

Suggested structure:

```text
metadata/
  en-US/
    name.txt
    subtitle.txt
    keywords.txt
    promotional_text.txt
    description.txt
    release_notes.txt
  zh-Hans/
    ...
  ja/
    ...
```

## 4. Localization generation tiers

AscendKit should support three user-selectable ranges:

### Tier 1 — major languages
A compact set of strategically important languages.

### Tier 2 — common languages
Roughly 8–12 broadly used locales.

### Tier 3 — maximum practical coverage
As many supported locales as feasible under App Store constraints and user goals.

## 5. Human review policy

AI-generated metadata should be treated as draft content until reviewed or explicitly accepted.

At minimum AscendKit should support:
- draft generation
- rewrite/regeneration
- linting
- acceptance state tracking

## 6. Linting rules

Linting should check:
- field length constraints
- locale completeness
- repeated phrases or low-signal keywords
- obvious placeholder text
- formatting issues
- URL validity where applicable
- suspicious translation artifacts

## 7. Auditability

The project should preserve:
- source language provenance
- localization generation strategy used
- review/acceptance status
- last modified source context

## 8. Agent assistance opportunities

AI can help with:
- first-pass product positioning copy
- audience-specific rewrites
- localization suggestions
- keyword refinement
- explanation of field-specific constraints

AI should not bypass linting or acceptance state.

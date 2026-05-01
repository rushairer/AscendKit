# AscendKit — Screenshot Intelligence

## 1. Purpose

AscendKit should not treat screenshots as a purely mechanical capture problem. It should help users decide what is worth showing, in what order, and why those choices support App Store conversion and reviewer clarity.

## 2. Two-layer screenshot system

### Layer A — Screenshot Intelligence
Responsible for:
- identifying likely hero features
- proposing screenshot-worthy user journeys
- recommending order and coverage
- spotting screens that are technically capturable but weak as marketing assets
- highlighting missing visual proof for important product claims

### Layer B — Screenshot Execution
Responsible for:
- UI-test-driven capture
- bring-your-own screenshot import
- completeness validation
- rounded corners
- device-frame composition
- poster-style composition
- artifact naming and output manifests

## 3. Inputs for screenshot intelligence

The first version should prefer structured, reviewable inputs over magical whole-codebase inference.

Suggested inputs:
- app category
- target audience
- short product positioning
- key features list
- important screens/pages list
- monetization surface notes (if any)
- platform matrix
- metadata draft context
- doctor findings that affect presentation risk

## 4. Outputs

- screenshot plan
- recommended screen order
- per-screen purpose notes
- hero-feature shortlist
- coverage gaps
- low-value screen warnings
- optional narrative recommendation

## 5. MVP posture

Screenshot intelligence should be in MVP, but in a constrained form:
- assist with structured planning
- explain why a screen is recommended
- review produced screenshots for obvious gaps or weak ordering
- avoid claiming deep semantic certainty without sufficient inputs

## 6. Non-goal for early versions

Do not assume the first public version can fully infer product strategy from raw SwiftUI source alone. Source inspection may assist, but should not be the only basis for screenshot recommendations.

## 7. Quality standard

AscendKit should help answer not only “do we have screenshots?” but also:
- do the screenshots reflect the app’s strongest value?
- is the order persuasive?
- is any critical product promise unsupported visually?
- is the first impression empty, generic, or misleading?

## 8. Relationship to doctor

Doctor should eventually include screenshot-readiness checks, while screenshot intelligence focuses on value judgment and planning quality. The two systems should inform each other but remain conceptually distinct.

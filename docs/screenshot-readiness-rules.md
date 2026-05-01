# AscendKit — Screenshot Readiness Rules

## 1. Purpose

If screenshots are core to MVP, AscendKit needs explicit rules for whether screenshot generation/import/composition is actually ready to run.

## 2. Two supported input paths

### Path A — UI Test Capture
Requirements to check:
- screenshot-capable UI test target exists
- stable launch arguments or launch mode exists for screenshot runs
- deterministic fixture or seeded data path exists where needed
- locale and device matrix is defined or derivable
- async loading risks are identified
- debug/test overlays are absent from release screenshots

### Path B — User-provided Screenshots
Requirements to check:
- source files meet expected dimensions/orientation rules
- directory structure is valid or mappable
- locale labeling is known
- device/platform labeling is known
- coverage is complete for required screenshot sets
- screenshots do not contain obvious debug/staging residue

## 3. Core readiness questions

AscendKit should answer:
- can screenshot production start now?
- what prerequisites are missing?
- which missing items are blockers vs warnings?
- is the current plan complete enough for the target platforms/locales?

## 4. High-value readiness rules to include

- missing UI test target for capture path
- no stable screenshot launch mode
- no fixture/seed data strategy where app requires content
- locale matrix incomplete for requested output scope
- raw screenshot count does not satisfy target set coverage
- debug banners, staging hosts, or test watermarks visible
- strong async instability risk for SwiftUI capture flows
- screenshot set covers app navigation but misses core selling points

## 5. Output expectations

Readiness evaluation should produce:
- structured findings
- missing prerequisite summary
- recommended next actions
- machine-readable classification for CI or agent consumers

## 6. Relationship to MVP

Screenshot readiness belongs in MVP because it protects the reliability of the screenshot pipeline. It is not enough to merely offer capture/compose commands without checking whether the inputs and workflow can succeed predictably.

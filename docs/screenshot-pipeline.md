# AscendKit — Screenshot Pipeline Strategy

## 1. Goal

Provide a modern screenshot workflow that does not depend on legacy fastlane snapshot/frameit-style coupling.

The pipeline should split into two independent but composable parts:
- capture
- composition

## 2. Capture principles

### 2.1 Official-tooling-first
Use Apple-supported project and test tooling as the primary capture mechanism.

### 2.2 Deterministic capture
Capture should rely on:
- explicit UI test flows
- stable launch arguments and fixtures
- explicit device and locale matrices
- predictable output naming

### 2.3 Separate capture from marketing composition
Raw screenshots are one artifact class.
Store-ready marketing/framed outputs are another.

## 3. Screenshot plan concept

Before capture, the user should define or accept a screenshot plan containing:
- target platforms
- device classes
- locales
- ordered screens to capture
- optional marketing titles or composition overlays

This prevents technically successful but marketing-useless screenshot generation.

## 4. Composition modes

AscendKit should support at least two modes:

### Mode A — device-frame composition
- rounded corners
- device frame assets for currently relevant App Store device sets
- optional localized title overlays

### Mode B — poster-style composition
- rounded screenshot cards
- background/layout templates
- no explicit device frame required

## 5. Device-frame support strategy

Do not attempt to support every historical Apple device.
Support the current minimum practical set relevant to App Store listing requirements.

Open questions for implementation:
- whether frame assets can be bundled legally
- whether users should import them
- whether setup should download versioned assets from a separately maintained source

## 6. Quality and safety checks

The screenshot pipeline should eventually detect or warn about:
- missing required screen counts
- locale/device coverage gaps
- placeholder UI
- debug banners or test overlays
- visible sensitive data in screenshots
- composition template mismatches

## 7. Output organization suggestion

```text
screenshots/
  plans/
  raw/
    en-US/
    zh-Hans/
  composed/
    device-frame/
    poster-style/
  manifests/
```

## 8. Why not bind everything to one monolith

Keeping capture and composition separate improves:
- debuggability
- reuse of existing screenshot sources
- legal flexibility for frame assets
- incremental delivery of product value

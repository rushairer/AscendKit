# Changelog

AscendKit follows [Semantic Versioning](https://semver.org/). During `0.y.z`, the project is usable but still evolving quickly; minor versions may introduce breaking workflow changes when needed, and patch versions are reserved for compatible fixes.

## 0.3.0 - 2026-05-01

### Added

- Local screenshot destination discovery and simulator recommendation for capture planning/workflows.
- Local screenshot workflow status report for capture, import, composition, workflow, and upload-plan readiness.
- Screenshot copy template initialization from `screenshot-plan.json` for framed poster title/subtitle editing.
- Screenshot copy refresh that preserves edited titles/subtitles while syncing to the current screenshot plan.
- Persisted screenshot copy linting against imported artifacts before framed poster composition.
- Local screenshot workflow copy refresh/lint when a copy file is supplied.
- Submission readiness gating for framed poster screenshot copy lint.
- Text submission readiness output now lists unsatisfied checklist items.
- Text screenshot upload-plan output now lists planning findings.
- Text screenshot readiness output now lists readiness findings and next actions.
- Text screenshot copy-lint output now lists missing or stale copy entries.
- Text screenshot workflow status output now lists workflow findings.

## 0.2.0 - 2026-05-01

### Added

- Agent release playbook for handing AscendKit to another AI agent without relying on a long one-off prompt.
- App Privacy workspace status, manual Data Not Collected confirmation, and submission readiness gating.
- Local screenshot capture planning that writes deterministic `xcodebuild test` commands without fastlane.
- Local screenshot capture execution with persisted result logs and automatic import manifest refresh.
- Local screenshot workflow command that runs capture planning, capture execution, import refresh, and composition in one deterministic step.

## 0.1.0 - 2026-05-01

Initial public MVP release.

### Added

- Local release workspaces under `.ascendkit/releases/<release-id>`.
- Xcode project intake, release doctor checks, readiness checks, and audit logs.
- Metadata templates, linting, local-vs-ASC diffing, ASC metadata request planning, and guarded metadata apply.
- ASC auth profiles with secret references stored outside the repository.
- ASC app lookup, build lookup, free pricing mutation, native screenshot upload, and guarded review submission execution.
- Screenshot planning, import, fastlane migration import, store-ready copy composition, poster composition, generic device frame composition, and App Store-sized framed poster composition with configurable copy.
- Reviewer information management and review handoff generation.
- Local IAP subscription template validation.

### Known Boundaries

- Binary upload is intentionally out of scope; use Xcode Cloud or Apple's upload tooling.
- App Privacy "Data Not Collected" publishing cannot be completed with an ASC API key in the tested environment because Apple's IRIS privacy endpoint rejects API-key JWT auth.
- Deep MCP integration is intentionally out of scope for this release.

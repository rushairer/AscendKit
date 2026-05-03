#!/usr/bin/env bash
set -euo pipefail

APP_ROOT=""
RELEASE_ID=""
ASC_PROFILE=""
PLAYBOOK_PATH="${ASCENDKIT_AGENT_PLAYBOOK_PATH:-}"
OUTPUT_PATH=""

usage() {
  cat <<USAGE
Usage: scripts/create-agent-handoff-prompt.sh --app-root PATH --release-id ID --asc-profile NAME [--playbook PATH] [--output FILE]

Creates a copyable prompt for handing an app release to an AI agent. The
generated prompt references AscendKit's agent release playbook and keeps
secrets, screenshots, reviewer data, binaries, and raw .ascendkit workspaces
out of the prompt.

This script is read-only. It does not inspect the app, mutate App Store
Connect, or write anything unless --output is provided.

Environment:
  ASCENDKIT_AGENT_PLAYBOOK_PATH   Default playbook path when --playbook is omitted.

Examples:
  scripts/create-agent-handoff-prompt.sh --app-root /path/to/App --release-id app-1.0-b1 --asc-profile production
  scripts/create-agent-handoff-prompt.sh --app-root /path/to/App --release-id app-1.0-b1 --asc-profile production --output /tmp/ascendkit-agent-prompt.txt
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app-root)
      APP_ROOT="${2:?Missing value for --app-root}"
      shift 2
      ;;
    --release-id)
      RELEASE_ID="${2:?Missing value for --release-id}"
      shift 2
      ;;
    --asc-profile)
      ASC_PROFILE="${2:?Missing value for --asc-profile}"
      shift 2
      ;;
    --playbook)
      PLAYBOOK_PATH="${2:?Missing value for --playbook}"
      shift 2
      ;;
    --output)
      OUTPUT_PATH="${2:?Missing value for --output}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 64
      ;;
  esac
done

if [[ -z "${APP_ROOT}" || -z "${RELEASE_ID}" || -z "${ASC_PROFILE}" ]]; then
  echo "Missing required --app-root, --release-id, or --asc-profile." >&2
  usage >&2
  exit 64
fi

if [[ -z "${PLAYBOOK_PATH}" ]]; then
  ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  PLAYBOOK_PATH="${ROOT_DIR}/docs/agent-release-playbook.md"
fi

WORKSPACE="${APP_ROOT%/}/.ascendkit/releases/${RELEASE_ID}"

PROMPT="$(cat <<PROMPT
Use AscendKit to prepare this Apple app for App Store submission.

App project root: ${APP_ROOT}
Release id: ${RELEASE_ID}
Release workspace: ${WORKSPACE}
ASC profile: ${ASC_PROFILE}
AscendKit playbook: ${PLAYBOOK_PATH}

Follow the playbook exactly. Use the installed \`ascendkit\` binary from PATH, not \`swift run\`, unless you are contributing to AscendKit itself.

Safety boundaries:
- Do not commit secrets, .ascendkit workspaces, screenshots, reviewer info, ASC identifiers, App Store Connect credentials, or generated release artifacts.
- Do not upload binaries. Xcode Cloud handles binary upload.
- Do not execute final remote review submission. AscendKit stops at \`submit handoff\`; complete final submission manually in App Store Connect.
- Before any remote ASC mutation, run the corresponding dry-run or plan command and inspect JSON output.
- Use \`--confirm-remote-mutation\` only for the specific intended ASC metadata, pricing, privacy, or screenshot mutation.
- If App Privacy cannot be published through the API, stop at the documented App Store Connect UI handoff and ask the user to confirm when it is published.

Start with:
\`\`\`bash
APP_ROOT="${APP_ROOT}"
RELEASE_ID="${RELEASE_ID}"
WORKSPACE="${WORKSPACE}"
ASC_PROFILE="${ASC_PROFILE}"

ascendkit --version
ascendkit intake inspect --root "\$APP_ROOT" --release-id "\$RELEASE_ID" --save --json
ascendkit workspace gitignore --workspace "\$WORKSPACE" --fix --json
ascendkit workspace next-steps --workspace "\$WORKSPACE" --json
\`\`\`

During the work, prefer \`workspace next-steps --json\`, \`workspace summary --json\`, \`workspace validate-handoff --json\`, and \`workspace export-summary --json\` over ad-hoc prose.

Finish by reporting:
- AscendKit version used.
- Bundle id, app version, build number, and selected ASC build.
- Metadata locales applied.
- Screenshot display types uploaded or exact screenshot blockers.
- Pricing result.
- App Privacy status.
- Review handoff status or exact remaining blockers.
- Validation commands run.
PROMPT
)"

if [[ -n "${OUTPUT_PATH}" ]]; then
  mkdir -p "$(dirname "${OUTPUT_PATH}")"
  printf '%s\n' "${PROMPT}" > "${OUTPUT_PATH}"
  echo "Wrote AscendKit agent handoff prompt to ${OUTPUT_PATH}"
else
  printf '%s\n' "${PROMPT}"
fi

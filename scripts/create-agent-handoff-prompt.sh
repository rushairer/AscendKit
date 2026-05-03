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
  scripts/create-agent-handoff-prompt.sh --app-root /Users/alex/Projects/AcmeWeather --release-id acme-weather-2.3.0-b4 --asc-profile acme-appstore-prod
  scripts/create-agent-handoff-prompt.sh --app-root /Users/alex/Projects/AcmeWeather --release-id acme-weather-2.3.0-b4 --asc-profile acme-appstore-prod --output /tmp/ascendkit-agent-prompt.txt
USAGE
}

reject_sample_value() {
  local label="$1"
  local value="$2"
  shift 2

  if [[ "${value}" == *"<<"*">>"* ]]; then
    echo "Refusing ${label}: replace <<...>> placeholders with a real value before generating an agent prompt." >&2
    exit 64
  fi

  local sample
  for sample in "$@"; do
    if [[ "${value}" == "${sample}" ]]; then
      echo "Refusing ${label}: '${value}' is a sample value. Provide the real app-specific value." >&2
      exit 64
    fi
  done
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

if [[ "${APP_ROOT}" != /* ]]; then
  echo "Refusing --app-root: provide an absolute path to the real app project root." >&2
  exit 64
fi

reject_sample_value "--app-root" "${APP_ROOT}" "/path/to/App" "/absolute/path/to/MyApp" "/Users/me/Projects/RealApp"
reject_sample_value "--release-id" "${RELEASE_ID}" "app-1.0-b1" "myapp-1.0-b1" "realapp-1.0-b1" "real-app-1.0-b1"
reject_sample_value "--asc-profile" "${ASC_PROFILE}" "PROFILE_NAME" "real-profile" "real-profile-name"

if [[ -z "${PLAYBOOK_PATH}" ]]; then
  ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  PLAYBOOK_PATH="${ROOT_DIR}/docs/agent-release-playbook.md"
fi

WORKSPACE="${APP_ROOT%/}/.ascendkit/releases/${RELEASE_ID}"

read -r -d '' PROMPT <<'PROMPT' || true
Use AscendKit to prepare this Apple app for App Store submission.

App project root: __ASCENDKIT_APP_ROOT__
Release id: __ASCENDKIT_RELEASE_ID__
Release workspace: __ASCENDKIT_WORKSPACE__
ASC profile: __ASCENDKIT_ASC_PROFILE__
AscendKit playbook: __ASCENDKIT_PLAYBOOK_PATH__

These are concrete values supplied by the user or maintainer. Do not replace them with sample values. If any path, release id, or ASC profile appears invalid, stop and ask the user instead of guessing.

Follow the playbook exactly. Use the installed ascendkit binary from PATH, not swift run, unless you are contributing to AscendKit itself.

Safety boundaries:
- Do not commit secrets, .ascendkit workspaces, screenshots, reviewer info, ASC identifiers, App Store Connect credentials, or generated release artifacts.
- Do not upload binaries. Xcode Cloud handles binary upload.
- Do not execute final remote review submission. AscendKit stops at submit handoff; complete final submission manually in App Store Connect.
- Before any remote ASC mutation, run the corresponding dry-run or plan command and inspect JSON output.
- Use --confirm-remote-mutation only for the specific intended ASC metadata, pricing, privacy, or screenshot mutation.
- If App Privacy cannot be published through the API, stop at the documented App Store Connect UI handoff and ask the user to confirm when it is published.

Start with these shell commands:

APP_ROOT="__ASCENDKIT_APP_ROOT__"
RELEASE_ID="__ASCENDKIT_RELEASE_ID__"
WORKSPACE="__ASCENDKIT_WORKSPACE__"
ASC_PROFILE="__ASCENDKIT_ASC_PROFILE__"

case "$APP_ROOT $RELEASE_ID $ASC_PROFILE" in
  *'<<'*'>>'*)
    echo "Stop: replace AscendKit prompt placeholders before running release commands." >&2
    exit 64
    ;;
esac

ascendkit --version
ascendkit intake inspect --root "$APP_ROOT" --release-id "$RELEASE_ID" --save --json
ascendkit workspace gitignore --workspace "$WORKSPACE" --fix --json
ascendkit workspace next-steps --workspace "$WORKSPACE" --json

During the work, prefer workspace next-steps --json, workspace summary --json, workspace validate-handoff --json, and workspace export-summary --json over ad-hoc prose.

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

PROMPT="${PROMPT//__ASCENDKIT_APP_ROOT__/${APP_ROOT}}"
PROMPT="${PROMPT//__ASCENDKIT_RELEASE_ID__/${RELEASE_ID}}"
PROMPT="${PROMPT//__ASCENDKIT_WORKSPACE__/${WORKSPACE}}"
PROMPT="${PROMPT//__ASCENDKIT_ASC_PROFILE__/${ASC_PROFILE}}"
PROMPT="${PROMPT//__ASCENDKIT_PLAYBOOK_PATH__/${PLAYBOOK_PATH}}"

if [[ -n "${OUTPUT_PATH}" ]]; then
  mkdir -p "$(dirname "${OUTPUT_PATH}")"
  printf '%s\n' "${PROMPT}" > "${OUTPUT_PATH}"
  echo "Wrote AscendKit agent handoff prompt to ${OUTPUT_PATH}"
else
  printf '%s\n' "${PROMPT}"
fi

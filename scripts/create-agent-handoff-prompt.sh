#!/usr/bin/env bash
set -euo pipefail

APP_ROOT=""
RELEASE_ID=""
WORKSPACE=""
ASC_PROFILE=""
PLAYBOOK_PATH="${ASCENDKIT_AGENT_PLAYBOOK_PATH:-}"
OUTPUT_PATH=""

usage() {
  cat <<USAGE
Usage: scripts/create-agent-handoff-prompt.sh (--app-root PATH --release-id ID | --workspace PATH) --asc-profile NAME [--playbook PATH_OR_URL] [--output FILE]

Contributor convenience wrapper around:
  ascendkit agent prompt (--app-root PATH --release-id ID | --workspace PATH) --asc-profile NAME

Normal users and release agents should use the installed ascendkit command
directly. This wrapper exists for source checkouts and keeps prompt generation
logic centralized in AscendKitCore instead of duplicating templates in shell.

Environment:
  ASCENDKIT_BIN                   AscendKit binary to run. Defaults to PATH lookup.
  ASCENDKIT_AGENT_PLAYBOOK_PATH   Default playbook path when --playbook is omitted.

Examples:
  scripts/create-agent-handoff-prompt.sh --app-root /Users/alex/Projects/AcmeWeather --release-id acme-weather-2.3.0-b4 --asc-profile acme-appstore-prod
  scripts/create-agent-handoff-prompt.sh --workspace /Users/alex/Projects/AcmeWeather/.ascendkit/releases/acme-weather-2.3.0-b4 --asc-profile acme-appstore-prod
  scripts/create-agent-handoff-prompt.sh --app-root /Users/alex/Projects/AcmeWeather --release-id acme-weather-2.3.0-b4 --asc-profile acme-appstore-prod --output /tmp/ascendkit-agent-prompt.txt
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
    --workspace)
      WORKSPACE="${2:?Missing value for --workspace}"
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

if [[ -z "${ASC_PROFILE}" || ( -z "${WORKSPACE}" && ( -z "${APP_ROOT}" || -z "${RELEASE_ID}" ) ) ]]; then
  echo "Missing required --asc-profile plus either --workspace or --app-root with --release-id." >&2
  usage >&2
  exit 64
fi

if [[ -z "${PLAYBOOK_PATH}" ]]; then
  ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  PLAYBOOK_PATH="${ROOT_DIR}/docs/agent-release-playbook.md"
fi

ARGS=(
  agent prompt
  --asc-profile "${ASC_PROFILE}"
  --playbook "${PLAYBOOK_PATH}"
)

if [[ -n "${WORKSPACE}" ]]; then
  ARGS+=(--workspace "${WORKSPACE}")
else
  ARGS+=(--app-root "${APP_ROOT}" --release-id "${RELEASE_ID}")
fi

if [[ -n "${OUTPUT_PATH}" ]]; then
  ARGS+=(--output "${OUTPUT_PATH}")
fi

if [[ -n "${ASCENDKIT_BIN:-}" ]]; then
  exec "${ASCENDKIT_BIN}" "${ARGS[@]}"
fi

if command -v ascendkit >/dev/null 2>&1; then
  exec ascendkit "${ARGS[@]}"
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"
exec swift run ascendkit "${ARGS[@]}"

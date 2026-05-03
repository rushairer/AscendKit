#!/usr/bin/env bash
set -euo pipefail

APP_ROOT=""
RELEASE_ID=""
ASCENDKIT_BIN="${ASCENDKIT_BIN:-ascendkit}"

usage() {
  cat <<USAGE
Usage: scripts/v1-representative-app-smoke.sh --app-root PATH [--release-id ID]

Runs the installed ascendkit binary against a representative app project to
verify the v1 release-readiness app-project gate without remote mutations.

Environment:
  ASCENDKIT_BIN   Binary to execute. Defaults to ascendkit from PATH.

Examples:
  scripts/v1-representative-app-smoke.sh --app-root /path/to/App
  ASCENDKIT_BIN=/opt/homebrew/bin/ascendkit scripts/v1-representative-app-smoke.sh --app-root /path/to/App --release-id v1-rc-smoke
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

if [[ -z "${APP_ROOT}" ]]; then
  echo "Missing required --app-root value." >&2
  usage >&2
  exit 64
fi

if ! command -v "${ASCENDKIT_BIN}" >/dev/null 2>&1; then
  echo "Missing ascendkit binary: ${ASCENDKIT_BIN}" >&2
  exit 69
fi

if [[ ! -d "${APP_ROOT}" ]]; then
  echo "App root does not exist: ${APP_ROOT}" >&2
  exit 66
fi

if [[ -z "${RELEASE_ID}" ]]; then
  RELEASE_ID="v1-rc-smoke-$(date +%Y%m%d%H%M%S)"
fi

WORKSPACE="${APP_ROOT}/.ascendkit/releases/${RELEASE_ID}"

echo "==> AscendKit binary"
"${ASCENDKIT_BIN}" --version
"${ASCENDKIT_BIN}" version --json >/dev/null

echo "==> Representative app workspace"
echo "APP_ROOT=${APP_ROOT}"
echo "RELEASE_ID=${RELEASE_ID}"
echo "WORKSPACE=${WORKSPACE}"

echo "==> Intake"
"${ASCENDKIT_BIN}" intake inspect --root "${APP_ROOT}" --release-id "${RELEASE_ID}" --save --json >/dev/null

echo "==> Workspace gitignore"
"${ASCENDKIT_BIN}" workspace gitignore --workspace "${WORKSPACE}" --fix --json >/dev/null

echo "==> Agent prompt"
"${ASCENDKIT_BIN}" agent prompt \
  --workspace "${WORKSPACE}" \
  --asc-profile representative-smoke-profile \
  --output "${WORKSPACE}/agent-prompt.txt" \
  --json >/dev/null

echo "==> Doctor"
"${ASCENDKIT_BIN}" doctor release --workspace "${WORKSPACE}" --json >/dev/null

echo "==> Metadata"
"${ASCENDKIT_BIN}" metadata init --workspace "${WORKSPACE}" --locale en-US --json >/dev/null
"${ASCENDKIT_BIN}" metadata lint --workspace "${WORKSPACE}" --locale en-US --json >/dev/null

echo "==> Screenshots"
"${ASCENDKIT_BIN}" screenshots plan \
  --workspace "${WORKSPACE}" \
  --screens Today,History,Settings \
  --features Focus,History,Notifications \
  --platforms iOS \
  --locales en-US \
  --json >/dev/null
"${ASCENDKIT_BIN}" screenshots copy init --workspace "${WORKSPACE}" --locale en-US --json >/dev/null
"${ASCENDKIT_BIN}" screenshots workflow status --workspace "${WORKSPACE}" --json >/dev/null

echo "==> ASC local status"
"${ASCENDKIT_BIN}" asc metadata status --workspace "${WORKSPACE}" --json >/dev/null
"${ASCENDKIT_BIN}" asc privacy status --workspace "${WORKSPACE}" --json >/dev/null

echo "==> Submission and handoff"
"${ASCENDKIT_BIN}" submit readiness --workspace "${WORKSPACE}" --json >/dev/null
"${ASCENDKIT_BIN}" workspace export-summary \
  --workspace "${WORKSPACE}" \
  --output "${WORKSPACE}/handoff-summary.json" \
  --json >/dev/null
"${ASCENDKIT_BIN}" workspace validate-handoff \
  --workspace "${WORKSPACE}" \
  --export "${WORKSPACE}/handoff-validation.json" \
  --json >/dev/null
"${ASCENDKIT_BIN}" workspace next-steps --workspace "${WORKSPACE}" --json >/dev/null

echo "Representative app smoke completed for ${RELEASE_ID}"

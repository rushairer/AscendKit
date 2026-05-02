#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${ASCENDKIT_VERSION:-}"
APP_ROOT="${ASCENDKIT_REPRESENTATIVE_APP_ROOT:-}"
ASCENDKIT_BIN="${ASCENDKIT_BIN:-ascendkit}"
SKIP_PUBLISHED=false
SKIP_HOMEBREW=false

usage() {
  cat <<USAGE
Usage: scripts/v1-release-readiness.sh --version VERSION --app-root PATH [--skip-published-release] [--skip-homebrew]

Runs the v1 release-readiness gates that combine local source checks,
published release asset verification, Homebrew install verification, and a
representative app smoke test using the installed AscendKit binary.

Environment:
  ASCENDKIT_VERSION                  Version to verify, for example 1.0.0 or v1.0.0.
  ASCENDKIT_REPRESENTATIVE_APP_ROOT  Representative app project root.
  ASCENDKIT_BIN                      Binary for representative app smoke. Defaults to ascendkit.

Examples:
  scripts/v1-release-readiness.sh --version 1.0.0 --app-root /path/to/App
  scripts/v1-release-readiness.sh --version v1.0.0 --app-root /path/to/App --skip-published-release
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      VERSION="${2:?Missing value for --version}"
      shift 2
      ;;
    --app-root)
      APP_ROOT="${2:?Missing value for --app-root}"
      shift 2
      ;;
    --skip-published-release)
      SKIP_PUBLISHED=true
      shift
      ;;
    --skip-homebrew)
      SKIP_HOMEBREW=true
      shift
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

if [[ -z "${VERSION}" ]]; then
  echo "Missing required --version value." >&2
  usage >&2
  exit 64
fi

if [[ -z "${APP_ROOT}" ]]; then
  echo "Missing required --app-root value." >&2
  usage >&2
  exit 64
fi

if [[ ! -d "${APP_ROOT}" ]]; then
  echo "Representative app root does not exist: ${APP_ROOT}" >&2
  exit 66
fi

VERSION="${VERSION#v}"

cd "${ROOT_DIR}"

echo "==> Local public release preflight"
scripts/preflight-public-release.sh

if [[ "${SKIP_PUBLISHED}" == false ]]; then
  echo "==> Published release assets"
  scripts/verify-release-assets.sh --version "${VERSION}"

  echo "==> Homebrew formula release sync"
  scripts/verify-homebrew-formula.sh --version "${VERSION}"
else
  echo "==> Skipping published release asset and formula verification"
fi

if [[ "${SKIP_HOMEBREW}" == false ]]; then
  echo "==> Homebrew reinstall"
  HOMEBREW_NO_AUTO_UPDATE=1 brew reinstall rushairer/ascendkit/ascendkit

  INSTALLED_VERSION="$("${ASCENDKIT_BIN}" --version)"
  if [[ "${INSTALLED_VERSION}" != "ascendkit ${VERSION}" ]]; then
    echo "Installed Homebrew binary version mismatch." >&2
    echo "Expected: ascendkit ${VERSION}" >&2
    echo "Actual:   ${INSTALLED_VERSION}" >&2
    exit 67
  fi

  "${ASCENDKIT_BIN}" version --json | grep -F "https://github.com/rushairer/AscendKit/releases/tag/v${VERSION}" >/dev/null
else
  echo "==> Skipping Homebrew reinstall"
fi

echo "==> Representative app smoke"
ASCENDKIT_BIN="${ASCENDKIT_BIN}" scripts/v1-representative-app-smoke.sh --app-root "${APP_ROOT}" --release-id "v1-readiness-${VERSION}"

echo "v1 release readiness gates passed for v${VERSION}"

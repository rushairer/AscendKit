#!/usr/bin/env bash
set -euo pipefail

REPOSITORY="${ASCENDKIT_GITHUB_REPOSITORY:-rushairer/AscendKit}"
VERSION="${ASCENDKIT_VERSION:-}"
TMP_DIR=""

usage() {
  cat <<USAGE
Usage: scripts/verify-release-assets.sh --version VERSION

Verifies that a GitHub Release contains the expected AscendKit distribution
assets, then performs a temporary installer-based smoke test.

Environment:
  ASCENDKIT_GITHUB_REPOSITORY   GitHub repository. Defaults to rushairer/AscendKit.
  ASCENDKIT_VERSION             Version to verify, for example 0.14.0 or v0.14.0.

Examples:
  scripts/verify-release-assets.sh --version 0.14.0
  ASCENDKIT_GITHUB_REPOSITORY=owner/AscendKit scripts/verify-release-assets.sh --version v0.14.0
USAGE
}

cleanup() {
  if [[ -n "${TMP_DIR}" && -d "${TMP_DIR}" ]]; then
    rm -rf "${TMP_DIR}"
  fi
}
trap cleanup EXIT

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      VERSION="${2:?Missing value for --version}"
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

require_tool() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required tool: $1" >&2
    exit 69
  fi
}

require_tool gh
require_tool uname

if [[ -z "${VERSION}" ]]; then
  echo "Missing required --version value." >&2
  usage >&2
  exit 64
fi

ARCH="$(uname -m)"
VERSION="${VERSION#v}"
TAG="v${VERSION}"
ARCHIVE_NAME="ascendkit-${VERSION}-macos-${ARCH}.tar.gz"
EXPECTED_ASSETS=(
  "${ARCHIVE_NAME}"
  "${ARCHIVE_NAME}.sha256"
  "ascendkit.rb"
  "install-ascendkit.sh"
)

ASSETS="$(gh release view "${TAG}" --repo "${REPOSITORY}" --json assets --jq '.assets[].name')"
for asset in "${EXPECTED_ASSETS[@]}"; do
  if ! grep -Fxq "${asset}" <<< "${ASSETS}"; then
    echo "Missing release asset for ${TAG}: ${asset}" >&2
    echo "Observed assets:" >&2
    echo "${ASSETS}" >&2
    exit 66
  fi
done

TMP_DIR="$(mktemp -d)"
scripts/install-ascendkit.sh --version "${VERSION}" --install-dir "${TMP_DIR}"
INSTALLED_VERSION="$("${TMP_DIR}/ascendkit" --version)"
if [[ "${INSTALLED_VERSION}" != "ascendkit ${VERSION}" ]]; then
  echo "Installed binary version mismatch." >&2
  echo "Expected: ascendkit ${VERSION}" >&2
  echo "Actual:   ${INSTALLED_VERSION}" >&2
  exit 67
fi

echo "Verified release assets and installer smoke test for ${TAG}"

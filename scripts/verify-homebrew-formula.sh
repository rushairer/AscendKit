#!/usr/bin/env bash
set -euo pipefail

REPOSITORY="${ASCENDKIT_GITHUB_REPOSITORY:-rushairer/AscendKit}"
VERSION="${ASCENDKIT_VERSION:-}"
FORMULA_PATH="${ASCENDKIT_FORMULA_PATH:-Formula/ascendkit.rb}"
ALLOW_MISSING_RELEASE=false

usage() {
  cat <<USAGE
Usage: scripts/verify-homebrew-formula.sh --version VERSION [--allow-missing-release]

Verifies that Formula/ascendkit.rb points at the published GitHub Release
archive and uses the release asset SHA-256 digest.

Environment:
  ASCENDKIT_GITHUB_REPOSITORY   GitHub repository. Defaults to rushairer/AscendKit.
  ASCENDKIT_FORMULA_PATH        Formula path. Defaults to Formula/ascendkit.rb.
  ASCENDKIT_VERSION             Version to verify, for example 0.18.0 or v0.18.0.

Examples:
  scripts/verify-homebrew-formula.sh --version 0.18.0
  scripts/verify-homebrew-formula.sh --version v0.18.0 --allow-missing-release
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      VERSION="${2:?Missing value for --version}"
      shift 2
      ;;
    --allow-missing-release)
      ALLOW_MISSING_RELEASE=true
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

require_tool() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required tool: $1" >&2
    exit 69
  fi
}

require_tool gh
require_tool uname
require_tool ruby

if [[ -z "${VERSION}" ]]; then
  echo "Missing required --version value." >&2
  usage >&2
  exit 64
fi

if [[ ! -f "${FORMULA_PATH}" ]]; then
  echo "Missing formula file: ${FORMULA_PATH}" >&2
  exit 66
fi

VERSION="${VERSION#v}"
TAG="v${VERSION}"
ARCHIVE_NAME="ascendkit-${VERSION}-macos-universal.tar.gz"
EXPECTED_URL="https://github.com/${REPOSITORY}/releases/download/${TAG}/${ARCHIVE_NAME}"

if ! gh release view "${TAG}" --repo "${REPOSITORY}" >/dev/null 2>&1; then
  if [[ "${ALLOW_MISSING_RELEASE}" == true ]]; then
    echo "Skipping Homebrew formula release verification because ${TAG} does not exist yet."
    exit 0
  fi
  echo "Missing GitHub Release: ${TAG}" >&2
  exit 66
fi

DIGEST="$(gh release view "${TAG}" --repo "${REPOSITORY}" --json assets \
  --jq ".assets[] | select(.name == \"${ARCHIVE_NAME}\") | .digest")"
EXPECTED_SHA="${DIGEST#sha256:}"
if [[ -z "${EXPECTED_SHA}" || "${EXPECTED_SHA}" == "${DIGEST}" ]]; then
  echo "Missing release archive digest for ${ARCHIVE_NAME} in ${TAG}." >&2
  exit 66
fi

ruby -c "${FORMULA_PATH}" >/dev/null

if ! grep -Fq "url \"${EXPECTED_URL}\"" "${FORMULA_PATH}"; then
  echo "Formula URL mismatch for ${TAG}." >&2
  echo "Expected: url \"${EXPECTED_URL}\"" >&2
  exit 67
fi

if ! grep -Fq "sha256 \"${EXPECTED_SHA}\"" "${FORMULA_PATH}"; then
  echo "Formula SHA-256 mismatch for ${TAG}." >&2
  echo "Expected: sha256 \"${EXPECTED_SHA}\"" >&2
  exit 67
fi

echo "Verified Homebrew formula for ${TAG}"

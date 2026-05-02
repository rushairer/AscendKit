#!/usr/bin/env bash
set -euo pipefail

REPOSITORY="${ASCENDKIT_GITHUB_REPOSITORY:-rushairer/AscendKit}"
INSTALL_DIR="${ASCENDKIT_INSTALL_DIR:-${HOME}/.local/bin}"
VERSION="${ASCENDKIT_VERSION:-latest}"
TMP_DIR=""

usage() {
  cat <<USAGE
Usage: scripts/install-ascendkit.sh [--version VERSION] [--install-dir DIR]

Downloads a macOS AscendKit release archive, verifies its SHA-256 checksum,
and installs the ascendkit CLI into DIR.

Environment:
  ASCENDKIT_VERSION             Version to install, for example 0.13.0 or v0.13.0.
  ASCENDKIT_INSTALL_DIR         Install directory. Defaults to ~/.local/bin.
  ASCENDKIT_GITHUB_REPOSITORY   GitHub repository. Defaults to rushairer/AscendKit.

Examples:
  scripts/install-ascendkit.sh --version 0.13.0
  ASCENDKIT_INSTALL_DIR=/usr/local/bin scripts/install-ascendkit.sh
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
    --install-dir)
      INSTALL_DIR="${2:?Missing value for --install-dir}"
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

require_tool curl
require_tool tar
require_tool shasum
require_tool install

download() {
  local url="$1"
  local output="$2"
  curl --fail --show-error --location --silent \
    --retry 3 \
    --retry-delay 2 \
    --retry-all-errors \
    --connect-timeout 15 \
    --max-time 120 \
    "${url}" \
    --output "${output}" && return 0

  if command -v gh >/dev/null 2>&1; then
    local asset_name
    asset_name="$(basename "${output}")"
    echo "curl download failed for ${asset_name}; retrying with gh release download." >&2
    rm -f "${output}"
    gh release download "v${VERSION}" \
      --repo "${REPOSITORY}" \
      --pattern "${asset_name}" \
      --dir "$(dirname "${output}")" \
      --clobber
    return 0
  fi

  return 1
}

ARCH="$(uname -m)"
if [[ "${ARCH}" != "arm64" ]]; then
  echo "Unsupported architecture: ${ARCH}. AscendKit release archives currently target macOS arm64." >&2
  exit 70
fi

if [[ "${VERSION}" == "latest" ]]; then
  LATEST_URL="$(curl --fail --silent --show-error --location --head \
    --retry 3 \
    --retry-delay 2 \
    --retry-all-errors \
    --connect-timeout 15 \
    --max-time 60 \
    --output /dev/null \
    --write-out '%{url_effective}' \
    "https://github.com/${REPOSITORY}/releases/latest")"
  VERSION="${LATEST_URL##*/}"
fi
VERSION="${VERSION#v}"

ARCHIVE_NAME="ascendkit-${VERSION}-macos-${ARCH}.tar.gz"
BASE_URL="https://github.com/${REPOSITORY}/releases/download/v${VERSION}"
ARCHIVE_URL="${BASE_URL}/${ARCHIVE_NAME}"
CHECKSUM_URL="${ARCHIVE_URL}.sha256"

TMP_DIR="$(mktemp -d)"
download "${ARCHIVE_URL}" "${TMP_DIR}/${ARCHIVE_NAME}"
download "${CHECKSUM_URL}" "${TMP_DIR}/${ARCHIVE_NAME}.sha256"

(
  cd "${TMP_DIR}"
  EXPECTED_SHA="$(awk '{print $1}' "${ARCHIVE_NAME}.sha256")"
  ACTUAL_SHA="$(shasum -a 256 "${ARCHIVE_NAME}" | awk '{print $1}')"
  if [[ "${EXPECTED_SHA}" != "${ACTUAL_SHA}" ]]; then
    echo "Checksum mismatch for ${ARCHIVE_NAME}" >&2
    echo "Expected: ${EXPECTED_SHA}" >&2
    echo "Actual:   ${ACTUAL_SHA}" >&2
    exit 65
  fi
  tar -xzf "${ARCHIVE_NAME}"
)

mkdir -p "${INSTALL_DIR}"
install -m 0755 "${TMP_DIR}/ascendkit-${VERSION}-macos-${ARCH}/bin/ascendkit" "${INSTALL_DIR}/ascendkit"

echo "Installed ascendkit ${VERSION} to ${INSTALL_DIR}/ascendkit"
echo "Run: ${INSTALL_DIR}/ascendkit --version"

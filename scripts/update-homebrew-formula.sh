#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${ROOT_DIR}/dist"
FORMULA_DIR="${ROOT_DIR}/Formula"
FORMULA_PATH="${FORMULA_DIR}/ascendkit.rb"
REPOSITORY="${ASCENDKIT_GITHUB_REPOSITORY:-rushairer/AscendKit}"
TMP_DIR=""

cleanup() {
  if [[ -n "${TMP_DIR}" && -d "${TMP_DIR}" ]]; then
    rm -rf "${TMP_DIR}"
  fi
}
trap cleanup EXIT

cd "${ROOT_DIR}"

BINARY_PATH="${ROOT_DIR}/.build/apple/Products/Release/ascendkit"
if [[ ! -x "${BINARY_PATH}" ]]; then
  swift build -c release --product ascendkit
  BINARY_PATH="${ROOT_DIR}/.build/release/ascendkit"
fi

VERSION="$("${BINARY_PATH}" --version | awk '{print $2}')"
ARCHIVE_PATH="${DIST_DIR}/ascendkit-${VERSION}-macos-universal.tar.gz"
CHECKSUM_PATH="${ARCHIVE_PATH}.sha256"

if [[ ! -f "${ARCHIVE_PATH}" || ! -f "${CHECKSUM_PATH}" ]]; then
  scripts/package-release.sh
fi

ARCHIVE_NAME="$(basename "${ARCHIVE_PATH}")"
SHA256="${ASCENDKIT_FORMULA_SHA256:-}"
SHA_SOURCE=""
RELEASE_EXISTS=false
if [[ -z "${SHA256}" ]] && command -v gh >/dev/null 2>&1; then
  if gh release view "v${VERSION}" --repo "${REPOSITORY}" >/dev/null 2>&1; then
    RELEASE_EXISTS=true
    DIGEST="$(gh release view "v${VERSION}" --repo "${REPOSITORY}" --json assets \
      --jq ".assets[] | select(.name == \"${ARCHIVE_NAME}\") | .digest" 2>/dev/null || true)"
    SHA256="${DIGEST#sha256:}"
    if [[ -n "${SHA256}" && "${SHA256}" != "${DIGEST}" ]]; then
      SHA_SOURCE="published release asset digest"
    else
      SHA256=""
    fi
  fi
fi

if [[ -z "${SHA256}" && "${RELEASE_EXISTS}" == true ]]; then
  TMP_DIR="$(mktemp -d)"
  if ! gh release download "v${VERSION}" \
    --repo "${REPOSITORY}" \
    --pattern "${ARCHIVE_NAME}" \
    --dir "${TMP_DIR}" >/dev/null; then
    echo "GitHub Release v${VERSION} exists, but ${ARCHIVE_NAME} could not be downloaded." >&2
    echo "Refusing to fall back to the local archive because that can create a stale Formula checksum." >&2
    exit 66
  fi
  SHA256="$(shasum -a 256 "${TMP_DIR}/${ARCHIVE_NAME}" | awk '{print $1}')"
  SHA_SOURCE="downloaded published release asset"
fi

if [[ -z "${SHA256}" ]]; then
  SHA256="$(awk '{print $1}' "${CHECKSUM_PATH}")"
  SHA_SOURCE="local release archive"
fi
if [[ -z "${SHA_SOURCE}" ]]; then
  SHA_SOURCE="ASCENDKIT_FORMULA_SHA256 override"
fi
URL="https://github.com/${REPOSITORY}/releases/download/v${VERSION}/${ARCHIVE_NAME}"

mkdir -p "${FORMULA_DIR}"
cat > "${FORMULA_PATH}" <<FORMULA
class Ascendkit < Formula
  desc "Local-first App Store release preparation toolkit"
  homepage "https://github.com/${REPOSITORY}"
  url "${URL}"
  sha256 "${SHA256}"
  license "MIT"

  def install
    bin.install "bin/ascendkit"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/ascendkit --version")
  end
end
FORMULA

ruby -c "${FORMULA_PATH}"
echo "Updated ${FORMULA_PATH}"
echo "Formula SHA-256 source: ${SHA_SOURCE}"

#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${ROOT_DIR}/dist"
FORMULA_DIR="${ROOT_DIR}/Formula"
FORMULA_PATH="${FORMULA_DIR}/ascendkit.rb"
REPOSITORY="${ASCENDKIT_GITHUB_REPOSITORY:-rushairer/AscendKit}"

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
if [[ -z "${SHA256}" ]] && command -v gh >/dev/null 2>&1; then
  DIGEST="$(gh release view "v${VERSION}" --repo "${REPOSITORY}" --json assets \
    --jq ".assets[] | select(.name == \"${ARCHIVE_NAME}\") | .digest" 2>/dev/null || true)"
  SHA256="${DIGEST#sha256:}"
fi
if [[ -z "${SHA256}" ]]; then
  SHA256="$(awk '{print $1}' "${CHECKSUM_PATH}")"
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

#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${ROOT_DIR}/dist"
WORK_DIR="${DIST_DIR}/.package-work"
ARCH="$(uname -m)"

cd "${ROOT_DIR}"

swift build -c release --product ascendkit

BINARY_PATH="${ROOT_DIR}/.build/release/ascendkit"
VERSION="$("${BINARY_PATH}" --version | awk '{print $2}')"
PACKAGE_NAME="ascendkit-${VERSION}-macos-${ARCH}"
PACKAGE_ROOT="${WORK_DIR}/${PACKAGE_NAME}"
ARCHIVE_PATH="${DIST_DIR}/${PACKAGE_NAME}.tar.gz"
CHECKSUM_PATH="${ARCHIVE_PATH}.sha256"

rm -rf "${WORK_DIR}"
mkdir -p "${PACKAGE_ROOT}/bin"

install -m 0755 "${BINARY_PATH}" "${PACKAGE_ROOT}/bin/ascendkit"
install -m 0644 "${ROOT_DIR}/LICENSE" "${PACKAGE_ROOT}/LICENSE"
install -m 0644 "${ROOT_DIR}/README.md" "${PACKAGE_ROOT}/README.md"

cat > "${PACKAGE_ROOT}/INSTALL.md" <<'INSTALL'
# AscendKit Binary Install

Install the bundled CLI by copying it to a directory on your `PATH`.

```bash
install -m 0755 bin/ascendkit ~/.local/bin/ascendkit
ascendkit --version
```

If `~/.local/bin` is not on your `PATH`, add it to your shell profile:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

This package contains the AscendKit CLI only. It does not contain app release
workspaces, App Store Connect credentials, screenshots, or app binaries.
INSTALL

mkdir -p "${DIST_DIR}"
tar -C "${WORK_DIR}" -czf "${ARCHIVE_PATH}" "${PACKAGE_NAME}"
shasum -a 256 "${ARCHIVE_PATH}" > "${CHECKSUM_PATH}"

echo "Created ${ARCHIVE_PATH}"
echo "Created ${CHECKSUM_PATH}"

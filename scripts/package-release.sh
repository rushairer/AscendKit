#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${ROOT_DIR}/dist"
WORK_DIR="${DIST_DIR}/.package-work"
PACKAGE_ARCH="${ASCENDKIT_PACKAGE_ARCH:-universal}"

cd "${ROOT_DIR}"

case "${PACKAGE_ARCH}" in
  universal)
    swift build -c release --product ascendkit --arch arm64 --arch x86_64
    BINARY_PATH="${ROOT_DIR}/.build/apple/Products/Release/ascendkit"
    ;;
  arm64|x86_64)
    swift build -c release --product ascendkit --arch "${PACKAGE_ARCH}"
    BINARY_PATH="${ROOT_DIR}/.build/apple/Products/Release/ascendkit"
    ;;
  native)
    swift build -c release --product ascendkit
    BINARY_PATH="${ROOT_DIR}/.build/release/ascendkit"
    PACKAGE_ARCH="$(uname -m)"
    ;;
  *)
    echo "Unsupported ASCENDKIT_PACKAGE_ARCH: ${PACKAGE_ARCH}" >&2
    echo "Expected universal, arm64, x86_64, or native." >&2
    exit 64
    ;;
esac

VERSION="$("${BINARY_PATH}" --version | awk '{print $2}')"
PACKAGE_NAME="ascendkit-${VERSION}-macos-${PACKAGE_ARCH}"
PACKAGE_ROOT="${WORK_DIR}/${PACKAGE_NAME}"
ARCHIVE_PATH="${DIST_DIR}/${PACKAGE_NAME}.tar.gz"
CHECKSUM_PATH="${ARCHIVE_PATH}.sha256"

rm -rf "${WORK_DIR}"
mkdir -p "${PACKAGE_ROOT}/bin"

install -m 0755 "${BINARY_PATH}" "${PACKAGE_ROOT}/bin/ascendkit"
install -m 0755 "${ROOT_DIR}/scripts/install-ascendkit.sh" "${PACKAGE_ROOT}/install-ascendkit.sh"
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
(
  cd "${DIST_DIR}"
  shasum -a 256 "${PACKAGE_NAME}.tar.gz" > "${PACKAGE_NAME}.tar.gz.sha256"
)

echo "Created ${ARCHIVE_PATH}"
echo "Created ${CHECKSUM_PATH}"

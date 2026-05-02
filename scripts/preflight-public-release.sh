#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

echo "==> Swift tests"
swift test

echo "==> CLI help smoke"
swift run ascendkit --help >/dev/null
swift run ascendkit version --json >/dev/null

echo "==> Shell syntax"
bash -n scripts/package-release.sh \
  scripts/update-homebrew-formula.sh \
  scripts/verify-homebrew-formula.sh \
  scripts/install-ascendkit.sh \
  scripts/verify-release-assets.sh \
  scripts/preflight-public-release.sh

echo "==> Release archive"
scripts/package-release.sh

echo "==> Release checksum"
VERSION="$(.build/release/ascendkit --version | awk '{print $2}')"
ARCH="$(uname -m)"
(
  cd dist
  shasum -a 256 -c "ascendkit-${VERSION}-macos-${ARCH}.tar.gz.sha256"
)

echo "==> Homebrew formula syntax"
scripts/update-homebrew-formula.sh
ruby -c Formula/ascendkit.rb

echo "==> Homebrew formula release sync"
scripts/verify-homebrew-formula.sh --version "${VERSION}" --allow-missing-release

echo "==> Whitespace"
git diff --check

echo "==> Sensitive marker scan"
rg -n --hidden \
  --glob '!.git/**' \
  --glob '!.build/**' \
  --glob '!.swiftpm/**' \
  --glob '!dist/**' \
  --glob '!*.png' \
  --glob '!*.jpg' \
  --glob '!*.jpeg' \
  "(BEGIN (EC|PRIVATE|OPENSSH)|PRIVATE KEY|bearer [A-Za-z0-9._-]+|AuthKey_[A-Z0-9]+|\\.p8)" . || true

cat <<'DONE'
==> Preflight complete

Review sensitive marker scan output manually. Expected matches are limited to
the scanner rules, README examples, and test fixtures.
DONE

#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${ASCENDKIT_VERSION:-}"
COMMIT=false
PUSH=false
REINSTALL=false

usage() {
  cat <<USAGE
Usage: scripts/finalize-homebrew-release.sh --version VERSION [--commit] [--push] [--reinstall]

Finalizes Homebrew distribution after the GitHub Release workflow has finished.
It refreshes Formula/ascendkit.rb from the published release asset digest,
verifies the formula, syncs the dedicated Homebrew tap, and optionally commits,
pushes, reinstalls, and diagnoses the installed Homebrew binary.

Environment:
  ASCENDKIT_VERSION   Version to finalize, for example 1.4.0 or v1.4.0.

Examples:
  scripts/finalize-homebrew-release.sh --version 1.4.0
  scripts/finalize-homebrew-release.sh --version v1.4.0 --commit --push --reinstall
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      VERSION="${2:?Missing value for --version}"
      shift 2
      ;;
    --commit)
      COMMIT=true
      shift
      ;;
    --push)
      COMMIT=true
      PUSH=true
      shift
      ;;
    --reinstall)
      REINSTALL=true
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

VERSION="${VERSION#v}"

cd "${ROOT_DIR}"

echo "==> Refreshing formula from published release asset"
scripts/update-homebrew-formula.sh

echo "==> Verifying formula against published release"
scripts/verify-homebrew-formula.sh --version "${VERSION}"

if [[ "${COMMIT}" == true ]]; then
  echo "==> Committing main formula if needed"
  git add Formula/ascendkit.rb
  if git diff --cached --quiet; then
    echo "Main formula already matches v${VERSION}."
  else
    git commit -m "Sync formula checksum for v${VERSION}"
  fi
fi

if [[ "${PUSH}" == true ]]; then
  echo "==> Pushing main"
  git push origin HEAD
fi

echo "==> Syncing Homebrew tap"
TAP_ARGS=()
if [[ "${COMMIT}" == true ]]; then
  TAP_ARGS+=(--commit)
fi
if [[ "${PUSH}" == true ]]; then
  TAP_ARGS+=(--push)
fi
if [[ "${#TAP_ARGS[@]}" -eq 0 ]]; then
  scripts/sync-homebrew-tap.sh
else
  scripts/sync-homebrew-tap.sh "${TAP_ARGS[@]}"
fi

if [[ "${REINSTALL}" == true ]]; then
  echo "==> Refreshing local tap checkout"
  TAP_REPO="$(brew --repo rushairer/ascendkit)"
  git -C "${TAP_REPO}" pull --ff-only

  echo "==> Reinstalling Homebrew formula"
  HOMEBREW_NO_AUTO_UPDATE=1 brew reinstall rushairer/ascendkit/ascendkit

  echo "==> Diagnosing Homebrew install"
  scripts/diagnose-homebrew-install.sh --version "${VERSION}"
fi

echo "Finalized Homebrew release for v${VERSION}"

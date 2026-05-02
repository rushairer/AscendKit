#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TAP_DIR="${ASCENDKIT_HOMEBREW_TAP_DIR:-${ROOT_DIR}/../homebrew-ascendkit}"
TAP_REMOTE="${ASCENDKIT_HOMEBREW_TAP_REMOTE:-git@github.com:rushairer/homebrew-ascendkit.git}"
COMMIT=false
PUSH=false

usage() {
  cat <<USAGE
Usage: scripts/sync-homebrew-tap.sh [--tap-dir PATH] [--commit] [--push]

Copies Formula/ascendkit.rb into the dedicated Homebrew tap checkout and
optionally commits and pushes the tap change.

Environment:
  ASCENDKIT_HOMEBREW_TAP_DIR     Tap checkout path. Defaults to ../homebrew-ascendkit.
  ASCENDKIT_HOMEBREW_TAP_REMOTE  Remote used when cloning a missing tap checkout.

Examples:
  scripts/sync-homebrew-tap.sh
  scripts/sync-homebrew-tap.sh --commit --push
  ASCENDKIT_HOMEBREW_TAP_DIR=/path/to/homebrew-ascendkit scripts/sync-homebrew-tap.sh --commit
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tap-dir)
      TAP_DIR="${2:?Missing value for --tap-dir}"
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

FORMULA_SOURCE="${ROOT_DIR}/Formula/ascendkit.rb"
if [[ ! -f "${FORMULA_SOURCE}" ]]; then
  echo "Missing source formula: ${FORMULA_SOURCE}" >&2
  exit 66
fi

if [[ ! -d "${TAP_DIR}/.git" ]]; then
  mkdir -p "$(dirname "${TAP_DIR}")"
  git clone "${TAP_REMOTE}" "${TAP_DIR}"
fi

mkdir -p "${TAP_DIR}/Formula"
cp "${FORMULA_SOURCE}" "${TAP_DIR}/Formula/ascendkit.rb"
ruby -c "${TAP_DIR}/Formula/ascendkit.rb"

if [[ "${COMMIT}" == true ]]; then
  VERSION="$(grep -Eo 'ascendkit-[0-9]+\.[0-9]+\.[0-9]+-macos' "${FORMULA_SOURCE}" | head -n 1 | sed -E 's/ascendkit-([0-9]+\.[0-9]+\.[0-9]+)-macos/\1/')"
  if [[ -z "${VERSION}" ]]; then
    echo "Could not infer formula version." >&2
    exit 65
  fi
  git -C "${TAP_DIR}" add Formula/ascendkit.rb
  if git -C "${TAP_DIR}" diff --cached --quiet; then
    echo "Homebrew tap formula already matches ${VERSION}."
  else
    git -C "${TAP_DIR}" commit -m "Update ascendkit to v${VERSION}"
  fi
fi

if [[ "${PUSH}" == true ]]; then
  git -C "${TAP_DIR}" push origin main
fi

git -C "${TAP_DIR}" status --short --branch

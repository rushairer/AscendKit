#!/usr/bin/env bash
set -uo pipefail

REPOSITORY="${ASCENDKIT_GITHUB_REPOSITORY:-rushairer/AscendKit}"
TAP="${ASCENDKIT_HOMEBREW_TAP:-rushairer/ascendkit}"
FORMULA_NAME="${ASCENDKIT_HOMEBREW_FORMULA:-ascendkit}"
VERSION="${ASCENDKIT_VERSION:-}"

usage() {
  cat <<USAGE
Usage: scripts/diagnose-homebrew-install.sh [--version VERSION]

Diagnoses Homebrew installation, tap, formula, and GitHub Release checksum
state for AscendKit. This script is read-only and prints repair commands
instead of mutating Homebrew state.

Environment:
  ASCENDKIT_GITHUB_REPOSITORY   GitHub repository. Defaults to rushairer/AscendKit.
  ASCENDKIT_HOMEBREW_TAP        Homebrew tap. Defaults to rushairer/ascendkit.
  ASCENDKIT_HOMEBREW_FORMULA    Formula name. Defaults to ascendkit.
  ASCENDKIT_VERSION             Expected version, for example 1.1.0 or v1.1.0.

Examples:
  scripts/diagnose-homebrew-install.sh
  scripts/diagnose-homebrew-install.sh --version 1.1.0
USAGE
}

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

VERSION="${VERSION#v}"
ISSUES=0

note() {
  echo "OK: $1"
}

warn() {
  echo "WARN: $1" >&2
  ISSUES=$((ISSUES + 1))
}

value_or_unknown() {
  if [[ -n "$1" ]]; then
    echo "$1"
  else
    echo "unknown"
  fi
}

extract_formula_value() {
  local key="$1"
  local path="$2"
  sed -nE "s/^[[:space:]]*${key}[[:space:]]+\"([^\"]+)\".*/\\1/p" "${path}" | head -n 1
}

echo "AscendKit Homebrew diagnostics"
echo

if ! command -v brew >/dev/null 2>&1; then
  warn "Homebrew is not installed or is not on PATH."
  echo
  echo "Repair:"
  echo "  Install Homebrew, then run:"
  echo "  brew tap ${TAP}"
  echo "  brew install ${FORMULA_NAME}"
  exit "${ISSUES}"
fi

note "Homebrew found at $(command -v brew)"

TAP_REPO="$(brew --repo "${TAP}" 2>/dev/null || true)"
if [[ -z "${TAP_REPO}" ]]; then
  warn "Homebrew tap ${TAP} is not installed."
else
  note "Tap ${TAP} found at ${TAP_REPO}"
fi

if [[ -n "${TAP_REPO}" && -d "${TAP_REPO}/.git" ]] && command -v git >/dev/null 2>&1; then
  TAP_REMOTE="$(git -C "${TAP_REPO}" remote get-url origin 2>/dev/null || true)"
  EXPECTED_TAP_REMOTE_HTTPS="https://github.com/${TAP%/*}/homebrew-${TAP#*/}.git"
  EXPECTED_TAP_REMOTE_SSH="git@github.com:${TAP%/*}/homebrew-${TAP#*/}.git"
  echo "Tap remote: $(value_or_unknown "${TAP_REMOTE}")"
  if [[ -n "${TAP_REMOTE}" && "${TAP_REMOTE}" != "${EXPECTED_TAP_REMOTE_HTTPS}" && "${TAP_REMOTE}" != "${EXPECTED_TAP_REMOTE_SSH}" ]]; then
    warn "Tap remote does not look like ${EXPECTED_TAP_REMOTE_HTTPS}."
  fi
fi

FORMULA_PATH=""
if [[ -n "${TAP_REPO}" && -f "${TAP_REPO}/Formula/${FORMULA_NAME}.rb" ]]; then
  FORMULA_PATH="${TAP_REPO}/Formula/${FORMULA_NAME}.rb"
else
  FORMULA_PATH="$(brew formula "${TAP}/${FORMULA_NAME}" 2>/dev/null || true)"
fi

if [[ -z "${FORMULA_PATH}" || ! -f "${FORMULA_PATH}" ]]; then
  warn "Formula ${TAP}/${FORMULA_NAME} was not found."
else
  note "Formula found at ${FORMULA_PATH}"
fi

FORMULA_URL=""
FORMULA_SHA=""
FORMULA_VERSION=""
if [[ -n "${FORMULA_PATH}" && -f "${FORMULA_PATH}" ]]; then
  FORMULA_URL="$(extract_formula_value "url" "${FORMULA_PATH}")"
  FORMULA_SHA="$(extract_formula_value "sha256" "${FORMULA_PATH}")"
  FORMULA_VERSION="$(echo "${FORMULA_URL}" | sed -nE 's#.*/releases/download/v([^/]+)/ascendkit-.*#\1#p')"
  echo "Formula URL: $(value_or_unknown "${FORMULA_URL}")"
  echo "Formula SHA-256: $(value_or_unknown "${FORMULA_SHA}")"
  echo "Formula version: $(value_or_unknown "${FORMULA_VERSION}")"
fi

if [[ -z "${VERSION}" ]]; then
  VERSION="${FORMULA_VERSION}"
fi

INSTALLED_VERSION=""
if command -v "${FORMULA_NAME}" >/dev/null 2>&1; then
  INSTALLED_PATH="$(command -v "${FORMULA_NAME}")"
  INSTALLED_VERSION="$("${FORMULA_NAME}" --version 2>/dev/null | awk '{print $2}' || true)"
  note "Installed binary found at ${INSTALLED_PATH}"
  echo "Installed version: $(value_or_unknown "${INSTALLED_VERSION}")"
  if command -v lipo >/dev/null 2>&1; then
    INSTALLED_ARCHS="$(lipo -archs "${INSTALLED_PATH}" 2>/dev/null || true)"
    echo "Installed architectures: $(value_or_unknown "${INSTALLED_ARCHS}")"
    if [[ -n "${INSTALLED_ARCHS}" && "${INSTALLED_ARCHS}" != *"arm64"* ]]; then
      warn "Installed binary does not report arm64 support."
    fi
    if [[ -n "${INSTALLED_ARCHS}" && "${INSTALLED_ARCHS}" != *"x86_64"* ]]; then
      warn "Installed binary does not report x86_64 support."
    fi
  fi
else
  warn "ascendkit binary is not installed or is not on PATH."
fi

if [[ -n "${VERSION}" ]]; then
  TAG="v${VERSION}"
  ARCHIVE_NAME="ascendkit-${VERSION}-macos-universal.tar.gz"
  EXPECTED_URL="https://github.com/${REPOSITORY}/releases/download/${TAG}/${ARCHIVE_NAME}"
  echo "Expected release URL: ${EXPECTED_URL}"

  if [[ -n "${FORMULA_URL}" && "${FORMULA_URL}" != "${EXPECTED_URL}" ]]; then
    warn "Formula URL does not match expected ${TAG} universal archive."
  fi
  if [[ -n "${INSTALLED_VERSION}" && "${INSTALLED_VERSION}" != "${VERSION}" ]]; then
    warn "Installed version ${INSTALLED_VERSION} does not match expected ${VERSION}."
  fi

  if command -v gh >/dev/null 2>&1; then
    if gh release view "${TAG}" --repo "${REPOSITORY}" >/dev/null 2>&1; then
      DIGEST="$(gh release view "${TAG}" --repo "${REPOSITORY}" --json assets \
        --jq ".assets[] | select(.name == \"${ARCHIVE_NAME}\") | .digest" 2>/dev/null || true)"
      RELEASE_SHA="${DIGEST#sha256:}"
      echo "Release SHA-256: $(value_or_unknown "${RELEASE_SHA}")"
      if [[ -z "${RELEASE_SHA}" || "${RELEASE_SHA}" == "${DIGEST}" ]]; then
        warn "GitHub Release asset digest is missing for ${ARCHIVE_NAME}."
      elif [[ -n "${FORMULA_SHA}" && "${FORMULA_SHA}" != "${RELEASE_SHA}" ]]; then
        warn "Formula SHA-256 does not match the GitHub Release asset digest."
      fi
    else
      warn "GitHub Release ${TAG} was not found in ${REPOSITORY}."
    fi
  else
    warn "GitHub CLI (gh) is not installed; skipped release digest comparison."
  fi
else
  warn "Could not infer expected AscendKit version. Pass --version VERSION."
fi

echo
if [[ "${ISSUES}" -eq 0 ]]; then
  echo "Diagnosis passed: Homebrew installation, tap, formula, and release digest are aligned."
  exit 0
fi

cat <<REPAIR
Diagnosis found ${ISSUES} issue(s).

Suggested repair commands:
  brew untap ${TAP} 2>/dev/null || true
  brew tap ${TAP}
  brew update
  brew reinstall ${TAP}/${FORMULA_NAME}
  ${FORMULA_NAME} --version

If the checksum still differs, ask the maintainer to run:
  scripts/update-homebrew-formula.sh
  scripts/verify-homebrew-formula.sh --version ${VERSION:-VERSION}
  scripts/sync-homebrew-tap.sh --commit --push
REPAIR

exit "${ISSUES}"

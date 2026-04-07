#!/usr/bin/env sh
# Install cryload from GitHub Releases (Linux, macOS, or Git Bash on Windows).
#
# Usage:
#   curl -sSfL https://raw.githubusercontent.com/sdogruyol/cryload/master/scripts/install.sh | sh -s
#   VERSION=v3.0.0 sh scripts/install.sh
#   INSTALL_DIR=/usr/local/bin sh scripts/install.sh
#
# Environment:
#   REPO         GitHub repo (default: sdogruyol/cryload)
#   VERSION      Release tag, e.g. v3.0.0 or 3.0.0; default: latest GitHub release
#   INSTALL_DIR  Directory for the binary (default: $HOME/.local/bin)
#   GITHUB_URL   Override base URL for enterprise mirrors (default: https://github.com)

set -eu

REPO="${REPO:-sdogruyol/cryload}"
GITHUB_URL="${GITHUB_URL:-https://github.com}"
VERSION="${VERSION:-}"

usage() {
  cat <<EOF
cryload install script

Environment variables:
  REPO         GitHub repository (default: sdogruyol/cryload)
  VERSION      Tag to install (e.g. v3.0.0); default: latest release
  INSTALL_DIR  Install destination (default: \$HOME/.local/bin)
  GITHUB_URL   GitHub base URL (default: https://github.com)

Example:
  curl -sSfL ${GITHUB_URL}/${REPO}/raw/master/scripts/install.sh | sh -s
  VERSION=v3.0.0 sh install.sh
EOF
}

for arg in "$@"; do
  case "$arg" in
    -h|--help) usage; exit 0 ;;
  esac
done

fetch() {
  url="$1"
  out="$2"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL -o "$out" "$url"
  elif command -v wget >/dev/null 2>&1; then
    wget -q -O "$out" "$url"
  else
    echo "install.sh: need curl or wget" >&2
    exit 1
  fi
}

fetch_stdout() {
  url="$1"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$url"
  elif command -v wget >/dev/null 2>&1; then
    wget -q -O - "$url"
  else
    echo "install.sh: need curl or wget" >&2
    exit 1
  fi
}

resolve_latest_tag() {
  json="$(fetch_stdout "https://api.github.com/repos/${REPO}/releases/latest")"
  tag="$(printf '%s' "$json" | tr -d '\r' | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -n 1)"
  if [ -z "$tag" ]; then
    echo "install.sh: could not resolve latest release tag" >&2
    exit 1
  fi
  printf '%s' "$tag"
}

normalize_tag() {
  v="$1"
  case "$v" in
    v*) printf '%s' "$v" ;;
    *) printf 'v%s' "$v" ;;
  esac
}

verify_sha256() {
  file="$1"
  sumfile="$2"
  expected="$(awk 'NF { print $1; exit }' "$sumfile")"
  if [ -z "$expected" ]; then
    echo "install.sh: empty checksum file" >&2
    return 1
  fi
  if command -v sha256sum >/dev/null 2>&1; then
    actual="$(sha256sum "$file" | awk '{ print $1 }')"
  elif command -v shasum >/dev/null 2>&1; then
    actual="$(shasum -a 256 "$file" | awk '{ print $1 }')"
  else
    echo "install.sh: need sha256sum or shasum for verification" >&2
    return 1
  fi
  if [ "$expected" != "$actual" ]; then
    echo "install.sh: SHA256 mismatch (expected $expected, got $actual)" >&2
    return 1
  fi
}

uname_s="$(uname -s 2>/dev/null || echo unknown)"
case "$uname_s" in
  Linux*) OS=linux; ASSET="cryload-linux"; BIN_NAME="cryload" ;;
  Darwin*) OS=macos; ASSET="cryload-macos"; BIN_NAME="cryload" ;;
  MINGW*|MSYS*|CYGWIN*)
    OS=windows
    ASSET="cryload-windows.exe"
    BIN_NAME="cryload.exe"
    ;;
  *)
    echo "install.sh: unsupported OS: $uname_s" >&2
    exit 1
    ;;
esac

if [ -z "${INSTALL_DIR:-}" ]; then
  INSTALL_DIR="${HOME}/.local/bin"
fi

if [ -z "$VERSION" ]; then
  TAG="$(resolve_latest_tag)"
else
  TAG="$(normalize_tag "$VERSION")"
fi

BASE="${GITHUB_URL}/${REPO}/releases/download/${TAG}"
SUM_ASSET="${ASSET}.sha256"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT INT

echo "Installing cryload ${TAG} for ${OS} -> ${INSTALL_DIR}/${BIN_NAME}"

fetch "${BASE}/${ASSET}" "${WORKDIR}/${ASSET}"
fetch "${BASE}/${SUM_ASSET}" "${WORKDIR}/${SUM_ASSET}"

verify_sha256 "${WORKDIR}/${ASSET}" "${WORKDIR}/${SUM_ASSET}"

mkdir -p "$INSTALL_DIR"
mv "${WORKDIR}/${ASSET}" "${INSTALL_DIR}/${BIN_NAME}"
if [ "$OS" != "windows" ]; then
  chmod +x "${INSTALL_DIR}/${BIN_NAME}"
fi

case ":${PATH:-}:" in
  *":${INSTALL_DIR}:"*) ;;
  *)
    echo
    echo "Add ${INSTALL_DIR} to your PATH, for example:"
    echo "  export PATH=\"${INSTALL_DIR}:\$PATH\""
    ;;
esac

echo "Done. Try: ${BIN_NAME} --help"

#!/usr/bin/env bash
set -euo pipefail

REPO='afmpjr/omarchy-orbital-theme'
REF="${ORBITAL_REF:-main}"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/orbital-install.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT

if [[ ! $REF =~ ^[A-Za-z0-9._/-]+$ || $REF == *..* ]]; then
  echo "Invalid ORBITAL_REF: $REF" >&2
  exit 2
fi
command -v curl >/dev/null 2>&1 || { echo 'curl is required.' >&2; exit 1; }
command -v tar >/dev/null 2>&1 || { echo 'tar is required.' >&2; exit 1; }
[[ -r /dev/tty ]] || { echo 'Orbital installation needs an interactive terminal.' >&2; exit 1; }

SOURCE_DIR="$TEMP_DIR/source"
mkdir -p "$SOURCE_DIR"
ARCHIVE_URL="https://github.com/$REPO/archive/$REF.tar.gz"
echo "Downloading Orbital from $REPO ($REF)..."
curl --fail --silent --show-error --location --retry 3 "$ARCHIVE_URL" \
  | tar --extract --gzip --strip-components=1 --no-same-owner --directory "$SOURCE_DIR"

[[ -x $SOURCE_DIR/install.sh ]] || { echo 'The downloaded archive has no executable install.sh.' >&2; exit 1; }
bash "$SOURCE_DIR/install.sh" "$@" < /dev/tty

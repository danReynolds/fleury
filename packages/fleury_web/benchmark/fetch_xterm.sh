#!/usr/bin/env bash
# Fetches the xterm.js UMD bundle + CSS into ./vendor (gitignored) so the
# head-to-head render benchmark can load it. Pinned to a known version for
# reproducible numbers. Requires npm.
set -euo pipefail

VERSION="${XTERM_VERSION:-6.0.0}"
DIR="$(cd "$(dirname "$0")" && pwd)"
VENDOR="$DIR/vendor"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "fetching @xterm/xterm@$VERSION …"
( cd "$TMP" && npm pack "@xterm/xterm@$VERSION" >/dev/null 2>&1 )
tar xzf "$TMP"/xterm-xterm-*.tgz -C "$TMP"

mkdir -p "$VENDOR"
cp "$TMP/package/lib/xterm.js" "$VENDOR/xterm.js"
cp "$TMP/package/css/xterm.css" "$VENDOR/xterm.css"
echo "vendored xterm.js ($(wc -c < "$VENDOR/xterm.js") bytes) + xterm.css into $VENDOR"

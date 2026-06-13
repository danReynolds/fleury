#!/usr/bin/env bash
# Fetches the xterm.js UMD bundle + CSS into ./vendor (gitignored) so the
# head-to-head render benchmark can load it. Pinned to a known version for
# reproducible numbers. Requires npm.
set -euo pipefail

# Pinned to a matched, stable xterm-5 set (the addons' stable releases peer
# `@xterm/xterm: ^5.0.0`; the xterm-6 addons are still beta). xterm 5 is also
# what the relay peers — ttyd/gotty/VS Code — actually ship today.
VERSION="${XTERM_VERSION:-5.5.0}"
DIR="$(cd "$(dirname "$0")" && pwd)"
VENDOR="$DIR/vendor"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

CANVAS_VERSION="${XTERM_CANVAS_VERSION:-0.7.0}"
WEBGL_VERSION="${XTERM_WEBGL_VERSION:-0.18.0}"

fetch() { # <npm-spec> <tgz-glob> <src-in-package> <dest>
  ( cd "$TMP" && npm pack "$1" >/dev/null 2>&1 )
  local d; d="$(mktemp -d "$TMP/x.XXXX")"
  tar xzf "$TMP"/$2 -C "$d"
  cp "$d/package/$3" "$VENDOR/$4"
}

mkdir -p "$VENDOR"
echo "fetching @xterm/xterm@$VERSION + canvas/webgl addons …"
fetch "@xterm/xterm@$VERSION"              'xterm-xterm-*.tgz'        lib/xterm.js          xterm.js
fetch "@xterm/xterm@$VERSION"              'xterm-xterm-*.tgz'        css/xterm.css         xterm.css
fetch "@xterm/addon-canvas@$CANVAS_VERSION" 'xterm-addon-canvas-*.tgz' lib/addon-canvas.js   addon-canvas.js
fetch "@xterm/addon-webgl@$WEBGL_VERSION"   'xterm-addon-webgl-*.tgz'  lib/addon-webgl.js    addon-webgl.js
echo "vendored xterm.js + css + canvas + webgl addons into $VENDOR"

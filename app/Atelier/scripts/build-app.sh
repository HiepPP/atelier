#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${1:-release}"

case "$CONFIGURATION" in
    debug|release) ;;
    *)
        echo "usage: $0 [debug|release]" >&2
        exit 2
        ;;
esac

cd "$ROOT"
swift build -c "$CONFIGURATION"
BIN_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path)"
APP="$ROOT/dist/Atelier.app"

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
install -m 0755 "$BIN_DIR/Atelier" "$APP/Contents/MacOS/Atelier"
install -m 0644 "$ROOT/Packaging/Info.plist" "$APP/Contents/Info.plist"

SWIFTTERM_BUNDLE="$BIN_DIR/SwiftTerm_SwiftTerm.bundle"
if [[ ! -d "$SWIFTTERM_BUNDLE" ]]; then
    echo "missing SwiftTerm resource bundle: $SWIFTTERM_BUNDLE" >&2
    exit 1
fi

ditto "$SWIFTTERM_BUNDLE" "$APP/Contents/Resources/SwiftTerm_SwiftTerm.bundle"
codesign --force --deep --sign - "$APP"
plutil -lint "$APP/Contents/Info.plist"
test -x "$APP/Contents/MacOS/Atelier"
codesign --verify --deep --strict --verbose=2 "$APP"

echo "$APP"

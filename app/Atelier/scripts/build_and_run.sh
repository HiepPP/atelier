#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Atelier"
BUNDLE_ID="app.atelier.Atelier"

case "$MODE" in
  --release|release)
    CONFIGURATION="release"
    ;;
  run|--debug|debug|--logs|logs|--telemetry|telemetry|--verify|verify)
    CONFIGURATION="debug"
    ;;
  *)
    echo "usage: $0 [run|--release|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
INSTALL_DIR="${ATELIER_INSTALL_DIR:-/Applications}"
INSTALLED_APP_BUNDLE="$INSTALL_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
INFO_PLIST_SOURCE="$ROOT_DIR/Packaging/Info.plist"
ICONSET_SOURCE="$ROOT_DIR/Resources/AppIcon.iconset"
FONT_SOURCE="$ROOT_DIR/Resources/Fonts"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

find_codesign_identity() {
  if [[ -n "${ATELIER_CODESIGN_IDENTITY:-}" ]]; then
    printf '%s\n' "$ATELIER_CODESIGN_IDENTITY"
    return
  fi

  local identities
  identities="$(security find-identity -p codesigning -v 2>/dev/null || true)"

  local identity
  identity="$(printf '%s\n' "$identities" | awk -F'"' '/Apple Development:/ { print $2; exit }')"
  if [[ -n "$identity" ]]; then
    printf '%s\n' "$identity"
    return
  fi

  identity="$(printf '%s\n' "$identities" | awk -F'"' '/Developer ID Application:/ { print $2; exit }')"
  if [[ -n "$identity" ]]; then
    printf '%s\n' "$identity"
  fi
}

sign_app_bundle() {
  local identity
  identity="$(find_codesign_identity)"

  if [[ -n "$identity" ]]; then
    echo "Signing $APP_NAME with $identity"
    codesign --force --deep --sign "$identity" --timestamp=none "$APP_BUNDLE"
  else
    echo "No Apple signing identity found. Falling back to ad hoc signing."
    echo "Documents access may prompt again until a real signing identity is available."
    codesign --force --deep --sign - --identifier "$BUNDLE_ID" "$APP_BUNDLE"
  fi

  codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
}

run_swiftlint() {
  if [[ "${ATELIER_SKIP_LINT:-0}" == "1" ]]; then
    echo "SwiftLint skipped (ATELIER_SKIP_LINT=1)."
    return
  fi
  if ! command -v swiftlint >/dev/null 2>&1; then
    echo "SwiftLint not installed. Install with: brew install swiftlint" >&2
    echo "Bypass with ATELIER_SKIP_LINT=1 (not recommended)." >&2
    exit 1
  fi
  echo "Running SwiftLint gate..."
  ( cd "$ROOT_DIR" && swiftlint lint --config "$ROOT_DIR/.swiftlint.yml" --quiet )
}

run_swiftlint

swift build --package-path "$ROOT_DIR" -c "$CONFIGURATION"
BUILD_DIR="$(swift build --package-path "$ROOT_DIR" -c "$CONFIGURATION" --show-bin-path)"
BUILD_BINARY="$BUILD_DIR/$APP_NAME"
RESOURCE_BUNDLES=(
  "Atelier_Atelier.bundle"
  "SwiftTerm_SwiftTerm.bundle"
  "HighlightSwift_HighlightSwift.bundle"
  "KeyboardShortcuts_KeyboardShortcuts.bundle"
  "Pow_Pow.bundle"
)

if [[ ! -x "$BUILD_BINARY" ]]; then
  echo "Build output not found: $BUILD_BINARY" >&2
  exit 1
fi

for bundle in "${RESOURCE_BUNDLES[@]}"; do
  if [[ ! -d "$BUILD_DIR/$bundle" ]]; then
    echo "Resource bundle not found: $BUILD_DIR/$bundle" >&2
    exit 1
  fi
done

if [[ ! -f "$INFO_PLIST_SOURCE" ]]; then
  echo "Bundle metadata not found: $INFO_PLIST_SOURCE" >&2
  exit 1
fi

if [[ ! -d "$ICONSET_SOURCE" ]]; then
  echo "App icon source not found: $ICONSET_SOURCE" >&2
  exit 1
fi

if [[ ! -f "$FONT_SOURCE/JetBrainsMono-Regular.ttf" ]]; then
  echo "Bundled font not found: $FONT_SOURCE/JetBrainsMono-Regular.ttf" >&2
  exit 1
fi

if [[ ! -f "$FONT_SOURCE/OFL.txt" ]]; then
  echo "Bundled font license not found: $FONT_SOURCE/OFL.txt" >&2
  exit 1
fi

mkdir -p "$APP_MACOS" "$APP_RESOURCES" "$APP_RESOURCES/Fonts"
iconutil -c icns "$ICONSET_SOURCE" -o "$APP_RESOURCES/AppIcon.icns"
cp -f "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"
for bundle in "${RESOURCE_BUNDLES[@]}"; do
  ditto "$BUILD_DIR/$bundle" "$APP_RESOURCES/$bundle"
done

cp -f "$FONT_SOURCE/JetBrainsMono-Regular.ttf" "$APP_RESOURCES/Fonts/"
cp -f "$FONT_SOURCE/OFL.txt" "$APP_RESOURCES/Fonts/"
cp -f "$INFO_PLIST_SOURCE" "$INFO_PLIST"

sign_app_bundle

install_app() {
  mkdir -p "$INSTALL_DIR"
  ditto "$APP_BUNDLE" "$INSTALLED_APP_BUNDLE"
}

open_app() {
  /usr/bin/open -n "$INSTALLED_APP_BUNDLE"
}

case "$MODE" in
  --release|release)
    echo "$APP_BUNDLE"
    ;;
  run)
    install_app
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    install_app
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    install_app
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    install_app
    open_app
    sleep 1
    pgrep -f "$INSTALLED_APP_BUNDLE/Contents/MacOS/$APP_NAME" >/dev/null
    ;;
esac

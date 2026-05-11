#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Lisdo"
APP_VERSION="${LISDO_APP_VERSION:-1.0}"
APP_DIR="${LISDO_APP_DIR:-$ROOT_DIR/dist/$APP_NAME.app}"
OUTPUT_DIR="${LISDO_RELEASE_DIR:-$ROOT_DIR/dist/release}"
ALLOW_AD_HOC="false"

usage() {
  cat <<'USAGE'
Usage: script/package_mac_release.sh [--allow-ad-hoc] [--help]

Package an already staged Lisdo.app into a GitHub Release DMG.

Options:
  --allow-ad-hoc  Permit ad-hoc signatures for local dry-run packaging only.
  --help          Show this help text.

Environment:
  LISDO_APP_VERSION  Controls the DMG filename. Defaults to 1.0.
  LISDO_APP_DIR      Path to an already staged Lisdo.app bundle.
  LISDO_RELEASE_DIR  Output directory. Defaults to dist/release.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --allow-ad-hoc)
      ALLOW_AD_HOC="true"
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 64
      ;;
  esac
  shift
done

SOURCE_APP_DIR="$APP_DIR"
PACKAGE_PATH="$OUTPUT_DIR/$APP_NAME-$APP_VERSION.dmg"
VOLUME_NAME="$APP_NAME $APP_VERSION"

if [[ ! -d "$SOURCE_APP_DIR" ]]; then
  echo "Staged app not found at $SOURCE_APP_DIR" >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/lisdo-dmg.XXXXXX")"

cleanup() {
  rm -rf "$STAGING_DIR"
}

trap cleanup EXIT

rm -f "$PACKAGE_PATH" "$PACKAGE_PATH.sha256"
if [[ "$ALLOW_AD_HOC" == "true" ]]; then
  /usr/bin/ditto --norsrc "$SOURCE_APP_DIR" "$STAGING_DIR/$APP_NAME.app"
else
  /usr/bin/ditto "$SOURCE_APP_DIR" "$STAGING_DIR/$APP_NAME.app"
fi
APP_DIR="$STAGING_DIR/$APP_NAME.app"

clean_bundle_metadata() {
  /usr/bin/xattr -cr "$APP_DIR" 2>/dev/null || true
  /usr/bin/xattr -d com.apple.FinderInfo "$APP_DIR" 2>/dev/null || true
  /usr/bin/xattr -d 'com.apple.fileprovider.fpfs#P' "$APP_DIR" 2>/dev/null || true
  /usr/bin/xattr -d com.apple.provenance "$APP_DIR" 2>/dev/null || true
}

require_bundle_value() {
  local key="$1"
  local expected="$2"
  local actual
  actual="$(/usr/libexec/PlistBuddy -c "Print :$key" "$APP_DIR/Contents/Info.plist")"
  if [[ "$actual" != "$expected" ]]; then
    echo "Info.plist $key mismatch: expected '$expected', got '$actual'" >&2
    exit 1
  fi
}

require_release_signature() {
  local codesign_info spctl_output
  codesign_info="$(codesign -dv --verbose=4 "$APP_DIR" 2>&1)"
  if grep -q '^Signature=adhoc$' <<< "$codesign_info"; then
    echo "Release packaging requires a Developer ID Application signature. Use --allow-ad-hoc only for local dry runs." >&2
    exit 1
  fi

  if grep -q '^Authority=Developer ID Application:' <<< "$codesign_info"; then
    return
  fi

  if spctl_output="$(spctl --assess --type execute --verbose=4 "$APP_DIR" 2>&1)"; then
    if grep -Eq 'source=(Notarized )?Developer ID' <<< "$spctl_output"; then
      return
    fi
  fi

  echo "Release packaging requires a Developer ID Application signature. Use --allow-ad-hoc only for local dry runs." >&2
  exit 1
}

require_entitlement_true() {
  local entitlement_key="$1"
  local entitlements_plist
  entitlements_plist="$(mktemp "${TMPDIR:-/tmp}/lisdo-entitlements.XXXXXX")"

  if ! codesign -d --entitlements :- "$APP_DIR" >"$entitlements_plist" 2>/dev/null; then
    rm -f "$entitlements_plist"
    echo "Could not inspect code signing entitlements for $APP_DIR." >&2
    exit 1
  fi

  local actual_value
  actual_value="$(/usr/libexec/PlistBuddy -c "Print :$entitlement_key" "$entitlements_plist" 2>/dev/null || true)"
  rm -f "$entitlements_plist"

  if [[ "$actual_value" != "true" ]]; then
    echo "$APP_DIR is missing required entitlement: $entitlement_key=true" >&2
    exit 1
  fi
}

if [[ "$ALLOW_AD_HOC" == "true" ]]; then
  clean_bundle_metadata
fi
EXECUTABLE_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP_DIR/Contents/Info.plist")"

if [[ ! -x "$APP_DIR/Contents/MacOS/$EXECUTABLE_NAME" ]]; then
  echo "App executable missing at $APP_DIR/Contents/MacOS/$EXECUTABLE_NAME" >&2
  exit 1
fi

require_bundle_value "CFBundleIdentifier" "com.yiwenwu.Lisdo.macOS"
require_bundle_value "CFBundleShortVersionString" "$APP_VERSION"
codesign --verify --strict --deep "$APP_DIR"
require_entitlement_true "com.apple.security.app-sandbox"
require_entitlement_true "com.apple.security.network.client"

if [[ "$ALLOW_AD_HOC" != "true" ]]; then
  require_release_signature
fi

ln -s /Applications "$STAGING_DIR/Applications"
hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$PACKAGE_PATH"

hdiutil verify "$PACKAGE_PATH"
shasum -a 256 "$PACKAGE_PATH" > "$PACKAGE_PATH.sha256"

echo "Packaged $PACKAGE_PATH"
echo "Wrote checksum $PACKAGE_PATH.sha256"

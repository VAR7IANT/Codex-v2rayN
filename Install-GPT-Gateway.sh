#!/bin/zsh
set -eu

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
LAUNCHER="$ROOT_DIR/build/GPTGatewayLauncher"
CHECKSUM_FILE="$ROOT_DIR/build/GPTGatewayLauncher.sha256"
GATEWAY_SCRIPT="$ROOT_DIR/src/gateway.zsh"
ICON_SOURCE="$ROOT_DIR/assets/GPT-Gateway.png"
VERSION="2.1.4"
BUILD_NUMBER="214"

INSTALL_ROOT="${GPT_GATEWAY_INSTALL_ROOT:-$HOME/Applications}"
APP_DIR="$INSTALL_ROOT/GPT Gateway.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This installer is for macOS only."
  exit 1
fi

if [[ ! -f "$LAUNCHER" ]]; then
  echo "Missing prebuilt native launcher: $LAUNCHER"
  echo "Use the versioned GPT Gateway macOS package from dist/."
  exit 1
fi

if [[ ! -f "$GATEWAY_SCRIPT" ]]; then
  echo "Missing gateway script: $GATEWAY_SCRIPT"
  exit 1
fi

if [[ ! -f "$ICON_SOURCE" ]]; then
  echo "Missing GPT Gateway icon: $ICON_SOURCE"
  exit 1
fi

ICON_WIDTH="$(/usr/bin/sips -g pixelWidth "$ICON_SOURCE" 2>/dev/null | /usr/bin/awk '/pixelWidth:/ {print $2}')"
ICON_HEIGHT="$(/usr/bin/sips -g pixelHeight "$ICON_SOURCE" 2>/dev/null | /usr/bin/awk '/pixelHeight:/ {print $2}')"
if [[ -z "$ICON_WIDTH" || -z "$ICON_HEIGHT" || "$ICON_WIDTH" != "$ICON_HEIGHT" || "$ICON_WIDTH" -lt 1024 ]]; then
  echo "The GPT Gateway icon must be a readable square PNG at least 1024 x 1024."
  echo "Detected: ${ICON_WIDTH:-unreadable} x ${ICON_HEIGHT:-unreadable}"
  exit 1
fi

if [[ -f "$CHECKSUM_FILE" ]]; then
  EXPECTED_SHA="$(awk '{print $1}' "$CHECKSUM_FILE")"
  ACTUAL_SHA="$(/usr/bin/shasum -a 256 "$LAUNCHER" | awk '{print $1}')"
  if [[ "$EXPECTED_SHA" != "$ACTUAL_SHA" ]]; then
    echo "The native launcher failed its SHA-256 integrity check."
    echo "Expected: $EXPECTED_SHA"
    echo "Actual:   $ACTUAL_SHA"
    echo "Download a fresh versioned package from dist/."
    exit 1
  fi
fi

ARCHS="$(/usr/bin/lipo -archs "$LAUNCHER" 2>/dev/null || true)"
printf 'Detected launcher architectures: %s\n' "${ARCHS:-unreadable}"
if [[ "$ARCHS" != *"arm64"* || "$ARCHS" != *"x86_64"* ]]; then
  echo "The launcher must contain both arm64 and x86_64 slices."
  /usr/bin/file "$LAUNCHER" 2>/dev/null || true
  echo "This usually means the package is stale or incomplete."
  echo "Use the versioned GPT Gateway macOS package from dist/."
  exit 1
fi

# Build the complete application away from ~/Applications first. This prevents
# Finder/LaunchServices from seeing a half-built bundle and caching the generic icon.
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT
STAGE_APP="$TMP_ROOT/GPT Gateway.app"
CONTENTS="$STAGE_APP/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
ICONSET="$TMP_ROOT/GPT-Gateway.iconset"
mkdir -p "$MACOS" "$RESOURCES" "$ICONSET" "$INSTALL_ROOT"

cp "$LAUNCHER" "$MACOS/GPTGatewayLauncher"
chmod +x "$MACOS/GPTGatewayLauncher"
cp "$GATEWAY_SCRIPT" "$RESOURCES/gateway.zsh"
chmod +x "$RESOURCES/gateway.zsh"

make_icon() {
  /usr/bin/sips -z "$1" "$1" "$ICON_SOURCE" --out "$ICONSET/$2" >/dev/null
  local width height
  width="$(/usr/bin/sips -g pixelWidth "$ICONSET/$2" 2>/dev/null | /usr/bin/awk '/pixelWidth:/ {print $2}')"
  height="$(/usr/bin/sips -g pixelHeight "$ICONSET/$2" 2>/dev/null | /usr/bin/awk '/pixelHeight:/ {print $2}')"
  if [[ "$width" != "$1" || "$height" != "$1" ]]; then
    echo "Invalid generated icon representation: $2 (${width:-?} x ${height:-?})"
    exit 1
  fi
}

make_icon 16 icon_16x16.png
make_icon 32 icon_16x16@2x.png
make_icon 32 icon_32x32.png
make_icon 64 icon_32x32@2x.png
make_icon 128 icon_128x128.png
make_icon 256 icon_128x128@2x.png
make_icon 256 icon_256x256.png
make_icon 512 icon_256x256@2x.png
make_icon 512 icon_512x512.png
make_icon 1024 icon_512x512@2x.png

if ! /usr/bin/iconutil -c icns "$ICONSET" -o "$RESOURCES/GPT-Gateway.icns"; then
  echo "Failed to create GPT-Gateway.icns from the user-provided icon."
  exit 1
fi

# A successful iconutil exit alone is not enough: prove the ICNS can be decoded
# back into the complete set of Apple icon representations before publishing.
ICON_CHECK="$TMP_ROOT/GPT-Gateway-check.iconset"
if ! /usr/bin/iconutil -c iconset "$RESOURCES/GPT-Gateway.icns" -o "$ICON_CHECK"; then
  echo "Generated GPT-Gateway.icns could not be decoded by iconutil."
  exit 1
fi
for icon_name in \
  icon_16x16.png icon_16x16@2x.png \
  icon_32x32.png icon_32x32@2x.png \
  icon_128x128.png icon_128x128@2x.png \
  icon_256x256.png icon_256x256@2x.png \
  icon_512x512.png; do
  if [[ ! -s "$ICON_CHECK/$icon_name" ]]; then
    echo "Generated GPT-Gateway.icns is missing $icon_name."
    exit 1
  fi
done
if [[ "$(/usr/bin/file -b "$RESOURCES/GPT-Gateway.icns")" != *"Mac OS X icon"* ]]; then
  echo "Generated GPT-Gateway.icns is not recognized as a macOS icon."
  exit 1
fi

cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>English</string>
  <key>CFBundleDisplayName</key>
  <string>GPT Gateway</string>
  <key>CFBundleExecutable</key>
  <string>GPTGatewayLauncher</string>
  <key>CFBundleIconFile</key>
  <string>GPT-Gateway.icns</string>
  <key>CFBundleIdentifier</key>
  <string>com.var7iant.gptgateway</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>GPT Gateway</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>${VERSION}</string>
  <key>CFBundleVersion</key>
  <string>${BUILD_NUMBER}</string>
  <key>LSMinimumSystemVersion</key>
  <string>12.0</string>
  <key>LSRequiresNativeExecution</key>
  <true/>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

/usr/bin/plutil -lint "$CONTENTS/Info.plist" >/dev/null
if [[ "$(/usr/bin/defaults read "$CONTENTS/Info" CFBundleIconFile 2>/dev/null || true)" != "GPT-Gateway.icns" ]]; then
  echo "CFBundleIconFile verification failed."
  exit 1
fi

if [[ -n "$(/usr/bin/defaults read "$CONTENTS/Info" CFBundleIconName 2>/dev/null || true)" ]]; then
  echo "CFBundleIconName must not be present without an asset catalog."
  exit 1
fi

/usr/bin/codesign --force --deep --sign - "$STAGE_APP" >/dev/null 2>&1
/usr/bin/codesign --verify --deep --strict "$STAGE_APP" >/dev/null 2>&1

# Only expose the app after every bundle file, plist check, icon check, native
# architecture check, and signature check has completed successfully.
if [[ -d "$APP_DIR" && -x "$LSREGISTER" ]]; then
  "$LSREGISTER" -u "$APP_DIR" >/dev/null 2>&1 || true
fi
rm -rf "$APP_DIR"
/bin/mv "$STAGE_APP" "$APP_DIR"
/usr/bin/xattr -dr com.apple.quarantine "$APP_DIR" >/dev/null 2>&1 || true
/usr/bin/touch "$APP_DIR" "$APP_DIR/Contents/Info.plist"
if [[ -x "$LSREGISTER" ]]; then
  "$LSREGISTER" -f "$APP_DIR" >/dev/null 2>&1 || true
fi

SELF_TEST="$("$APP_DIR/Contents/MacOS/GPTGatewayLauncher" --native-self-test 2>/dev/null || true)"
if [[ "$(uname -m)" == "arm64" ]]; then
  if [[ "$SELF_TEST" != *"arch=arm64"* || "$SELF_TEST" != *"translated=0"* ]]; then
    echo "Native Apple silicon self-test failed: ${SELF_TEST:-no output}"
    rm -rf "$APP_DIR"
    exit 1
  fi
fi

printf '\nInstalled: %s\n' "$APP_DIR"
printf 'Version: %s\n' "$VERSION"
printf 'Native launcher architectures: %s\n' "$ARCHS"
printf 'Native self-test: %s\n' "$SELF_TEST"
printf 'Rosetta: not required (LSRequiresNativeExecution = true)\n'
printf 'Proxy default: socks5://127.0.0.1:10808\n'
printf 'User-provided icon: installed and registered\n'
printf '\nOpen Finder > Home > Applications and launch GPT Gateway\n\n'

if [[ -z "${GPT_GATEWAY_SKIP_OPEN:-}" ]]; then
  /usr/bin/open "$INSTALL_ROOT"
fi

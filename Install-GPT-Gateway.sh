#!/bin/zsh
set -eu

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
LAUNCHER="$ROOT_DIR/build/GPTGatewayLauncher"
CHECKSUM_FILE="$ROOT_DIR/build/GPTGatewayLauncher.sha256"
GATEWAY_SCRIPT="$ROOT_DIR/src/gateway.zsh"
ICON_SOURCE="$ROOT_DIR/assets/GPT-Gateway.png"
VERSION="2.1.1"

INSTALL_ROOT="${GPT_GATEWAY_INSTALL_ROOT:-$HOME/Applications}"
APP_DIR="$INSTALL_ROOT/GPT Gateway.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This installer is for macOS only."
  exit 1
fi

if [[ ! -f "$LAUNCHER" ]]; then
  echo "Missing prebuilt native launcher: $LAUNCHER"
  echo "Use the versioned GPT Gateway macOS package from dist/."
  exit 1
fi

# ZIP extraction tools do not always preserve Unix executable bits.
chmod +x "$LAUNCHER" 2>/dev/null || true

if [[ ! -x "$LAUNCHER" ]]; then
  echo "The native launcher could not be made executable: $LAUNCHER"
  exit 1
fi

if [[ ! -f "$GATEWAY_SCRIPT" ]]; then
  echo "Missing gateway script: $GATEWAY_SCRIPT"
  exit 1
fi
chmod +x "$GATEWAY_SCRIPT" 2>/dev/null || true

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

if [[ "$ARCHS" != *"arm64"* ]]; then
  echo "The launcher does not contain an arm64 slice."
  /usr/bin/file "$LAUNCHER" 2>/dev/null || true
  echo "This usually means the package is stale or incomplete."
  echo "Use the versioned GPT Gateway macOS package from dist/."
  exit 1
fi

rm -rf "$APP_DIR"
mkdir -p "$MACOS" "$RESOURCES"

cp "$LAUNCHER" "$MACOS/GPTGatewayLauncher"
chmod +x "$MACOS/GPTGatewayLauncher"

cp "$GATEWAY_SCRIPT" "$RESOURCES/gateway.zsh"
chmod +x "$RESOURCES/gateway.zsh"

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
  <string>211</string>
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

ICON_INSTALLED=false
if [[ -f "$ICON_SOURCE" ]]; then
  TMP_DIR="$(mktemp -d)"
  trap 'rm -rf "$TMP_DIR"' EXIT
  ICONSET="$TMP_DIR/GPT-Gateway.iconset"
  mkdir -p "$ICONSET"

  make_icon() {
    /usr/bin/sips -z "$1" "$1" "$ICON_SOURCE" --out "$ICONSET/$2" >/dev/null
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

  if /usr/bin/iconutil -c icns "$ICONSET" -o "$RESOURCES/GPT-Gateway.icns" >/dev/null 2>&1; then
    /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string GPT-Gateway.icns" "$CONTENTS/Info.plist" >/dev/null
    ICON_INSTALLED=true
  fi
fi

/usr/bin/plutil -lint "$CONTENTS/Info.plist" >/dev/null
/usr/bin/codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1
/usr/bin/xattr -dr com.apple.quarantine "$APP_DIR" >/dev/null 2>&1 || true

SELF_TEST="$("$MACOS/GPTGatewayLauncher" --native-self-test 2>/dev/null || true)"
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
if [[ "$ICON_INSTALLED" == true ]]; then
  printf 'User-provided icon: installed\n'
fi
printf '\nOpen Finder > Home > Applications and launch GPT Gateway\n\n'

if [[ -z "${GPT_GATEWAY_SKIP_OPEN:-}" ]]; then
  /usr/bin/open "$INSTALL_ROOT"
fi

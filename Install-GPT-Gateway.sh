#!/bin/zsh
set -eu

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
LAUNCHER="$ROOT_DIR/build/GPTGatewayLauncher"
GATEWAY_SCRIPT="$ROOT_DIR/src/gateway.zsh"
ICON_SOURCE="$ROOT_DIR/assets/GPT-Gateway.svg"

INSTALL_ROOT="${GPT_GATEWAY_INSTALL_ROOT:-$HOME/Applications}"
APP_DIR="$INSTALL_ROOT/GPT Gateway.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This installer is for macOS only."
  exit 1
fi

if [[ ! -x "$LAUNCHER" ]]; then
  echo "Missing prebuilt native launcher: $LAUNCHER"
  echo "Download the complete branch ZIP after the macOS build has finished."
  exit 1
fi

if [[ ! -f "$GATEWAY_SCRIPT" ]]; then
  echo "Missing gateway script: $GATEWAY_SCRIPT"
  exit 1
fi

ARCHS="$(/usr/bin/lipo -archs "$LAUNCHER" 2>/dev/null || true)"
if [[ "$ARCHS" != *"arm64"* ]]; then
  echo "The launcher does not contain an arm64 slice."
  exit 1
fi

rm -rf "$APP_DIR"
mkdir -p "$MACOS" "$RESOURCES"

cp "$LAUNCHER" "$MACOS/GPTGatewayLauncher"
chmod +x "$MACOS/GPTGatewayLauncher"

cp "$GATEWAY_SCRIPT" "$RESOURCES/gateway.zsh"
chmod +x "$RESOURCES/gateway.zsh"

cat > "$CONTENTS/Info.plist" <<'PLIST'
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
  <string>2.0.0</string>
  <key>CFBundleVersion</key>
  <string>200</string>
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
  PREVIEW="$TMP_DIR/preview"
  ICONSET="$TMP_DIR/GPT-Gateway.iconset"
  mkdir -p "$PREVIEW" "$ICONSET"

  if /usr/bin/qlmanage -t -s 1024 -o "$PREVIEW" "$ICON_SOURCE" >/dev/null 2>&1; then
    PNG="$PREVIEW/$(basename "$ICON_SOURCE").png"
    if [[ -f "$PNG" ]]; then
      make_icon() {
        /usr/bin/sips -z "$1" "$1" "$PNG" --out "$ICONSET/$2" >/dev/null
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
      cp "$PNG" "$ICONSET/icon_512x512@2x.png"

      if /usr/bin/iconutil -c icns "$ICONSET" -o "$RESOURCES/GPT-Gateway.icns" >/dev/null 2>&1; then
        /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string GPT-Gateway.icns" "$CONTENTS/Info.plist" >/dev/null
        ICON_INSTALLED=true
      fi
    fi
  fi
fi

/usr/bin/plutil -lint "$CONTENTS/Info.plist" >/dev/null
/usr/bin/codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1
/usr/bin/xattr -dr com.apple.quarantine "$APP_DIR" >/dev/null 2>&1 || true

printf '\nInstalled: %s\n' "$APP_DIR"
printf 'Native launcher architectures: %s\n' "$ARCHS"
printf 'Rosetta: not required (LSRequiresNativeExecution = true)\n'
printf 'Proxy default: socks5://127.0.0.1:10808\n'
if [[ "$ICON_INSTALLED" == true ]]; then
  printf 'Custom icon: installed\n'
fi
printf '\nOpen Finder > Home > Applications and launch GPT Gateway\n\n'

if [[ -z "${GPT_GATEWAY_SKIP_OPEN:-}" ]]; then
  /usr/bin/open "$INSTALL_ROOT"
fi

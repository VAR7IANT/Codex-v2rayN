#!/bin/zsh
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_SCRIPT="$SCRIPT_DIR/GPT-Gateway.command"
ICON_SOURCE="$SCRIPT_DIR/assets/GPT-Gateway.svg"
INSTALL_ROOT="$HOME/Applications"
APP_DIR="$INSTALL_ROOT/GPT Gateway.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

if [[ ! -f "$SOURCE_SCRIPT" ]]; then
  echo "GPT-Gateway.command was not found beside this installer."
  exit 1
fi

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$SOURCE_SCRIPT" "$RESOURCES_DIR/GPT-Gateway.command"
chmod +x "$RESOURCES_DIR/GPT-Gateway.command"

cat > "$MACOS_DIR/GPT-Gateway" <<'RUNNER'
#!/bin/zsh
set -eu
APP_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
exec "$APP_DIR/Contents/Resources/GPT-Gateway.command"
RUNNER
chmod +x "$MACOS_DIR/GPT-Gateway"

ICON_INSTALLED=false
if [[ -f "$ICON_SOURCE" ]]; then
  PREVIEW_DIR="$TMP_DIR/preview"
  ICONSET_DIR="$TMP_DIR/GPT-Gateway.iconset"
  mkdir -p "$PREVIEW_DIR" "$ICONSET_DIR"

  # qlmanage is built into macOS and can rasterize the SVG without requiring
  # Homebrew, Python, ImageMagick, or Xcode.
  if /usr/bin/qlmanage -t -s 1024 -o "$PREVIEW_DIR" "$ICON_SOURCE" >/dev/null 2>&1; then
    RASTER="$PREVIEW_DIR/$(basename "$ICON_SOURCE").png"
    if [[ -f "$RASTER" ]]; then
      make_icon() {
        local pixels="$1"
        local filename="$2"
        /usr/bin/sips -z "$pixels" "$pixels" "$RASTER" --out "$ICONSET_DIR/$filename" >/dev/null
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
      cp "$RASTER" "$ICONSET_DIR/icon_512x512@2x.png"

      if /usr/bin/iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES_DIR/GPT-Gateway.icns" >/dev/null 2>&1; then
        ICON_INSTALLED=true
      fi
    fi
  fi
fi

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>English</string>
  <key>CFBundleDisplayName</key>
  <string>GPT Gateway</string>
  <key>CFBundleExecutable</key>
  <string>GPT-Gateway</string>
  <key>CFBundleIdentifier</key>
  <string>com.var7iant.gptgateway</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>GPT Gateway</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.1.0</string>
  <key>CFBundleVersion</key>
  <string>2</string>
  <key>CFBundleIconFile</key>
  <string>GPT-Gateway</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

# Remove stale quarantine metadata from the locally generated wrapper only.
/usr/bin/xattr -dr com.apple.quarantine "$APP_DIR" 2>/dev/null || true

# Refresh Launch Services / Finder icon metadata where possible.
/usr/bin/touch "$APP_DIR"

printf '\nInstalled: %s\n' "$APP_DIR"
printf 'Proxy default: socks5://127.0.0.1:10808\n'
if [[ "$ICON_INSTALLED" == true ]]; then
  printf 'Custom GPT Gateway icon: installed\n'
else
  printf 'Custom icon: skipped (the launcher still works normally)\n'
fi
printf '\nOpen Finder > Home > Applications and double-click GPT Gateway.\n'
printf 'You can also drag GPT Gateway.app into the Dock.\n\n'
/usr/bin/open "$INSTALL_ROOT"

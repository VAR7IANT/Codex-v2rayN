#!/bin/zsh
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_SCRIPT="$SCRIPT_DIR/GPT-Gateway.command"
INSTALL_ROOT="$HOME/Applications"
APP_DIR="$INSTALL_ROOT/GPT Gateway.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

if [[ ! -f "$SOURCE_SCRIPT" ]]; then
  echo "GPT-Gateway.command was not found beside this installer."
  exit 1
fi

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
  <string>1.0.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSUIElement</key>
  <true/>
</dict>
</plist>
PLIST

# Remove stale quarantine metadata from the locally generated wrapper only.
/usr/bin/xattr -dr com.apple.quarantine "$APP_DIR" 2>/dev/null || true

printf '\nInstalled: %s\n' "$APP_DIR"
printf 'Proxy default: socks5://127.0.0.1:10808\n'
printf 'Open Finder > Applications in your Home folder, then double-click GPT Gateway.\n\n'
/usr/bin/open "$INSTALL_ROOT"

#!/bin/zsh
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_SCRIPT="$SCRIPT_DIR/GPT-Gateway.command"
ICON_SOURCE="$SCRIPT_DIR/assets/GPT-Gateway.svg"
INSTALL_ROOT="$HOME/Applications"
APP_DIR="$INSTALL_ROOT/GPT Gateway.app"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

if [[ ! -f "$SOURCE_SCRIPT" ]]; then
  echo "GPT-Gateway.command was not found beside this installer."
  exit 1
fi

mkdir -p "$INSTALL_ROOT"
rm -rf "$APP_DIR"

# Build the wrapper as a macOS AppleScript applet. Script-only apps can be
# conservatively selected for Rosetta by LaunchServices on Apple silicon, so
# LSArchitecturePriority is set below with arm64 first as recommended by Apple.
APPLET_SOURCE="$TMP_DIR/GPT-Gateway.applescript"
cat > "$APPLET_SOURCE" <<'APPLESCRIPT'
on run
  try
    set appRoot to POSIX path of (path to me)
    set gatewayScript to appRoot & "Contents/Resources/GPT-Gateway.command"
    do shell script "/usr/bin/nohup /bin/zsh " & quoted form of gatewayScript & " >/dev/null 2>&1 < /dev/null &"
  on error errMsg
    display alert "GPT Gateway" message errMsg as critical buttons {"OK"} default button "OK"
  end try
end run
APPLESCRIPT

/usr/bin/osacompile -o "$APP_DIR" "$APPLET_SOURCE"

CONTENTS_DIR="$APP_DIR/Contents"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
PLIST="$CONTENTS_DIR/Info.plist"

cp "$SOURCE_SCRIPT" "$RESOURCES_DIR/GPT-Gateway.command"
chmod +x "$RESOURCES_DIR/GPT-Gateway.command"

set_plist_string() {
  local key="$1"
  local value="$2"
  /usr/libexec/PlistBuddy -c "Set :$key $value" "$PLIST" >/dev/null 2>&1 || \
    /usr/libexec/PlistBuddy -c "Add :$key string $value" "$PLIST" >/dev/null
}

set_plist_string CFBundleIdentifier com.var7iant.gptgateway
set_plist_string CFBundleName "GPT Gateway"
set_plist_string CFBundleDisplayName "GPT Gateway"
set_plist_string CFBundleShortVersionString 1.3.0
set_plist_string CFBundleVersion 4
set_plist_string LSMinimumSystemVersion 14.0

/usr/libexec/PlistBuddy -c "Set :NSHighResolutionCapable true" "$PLIST" >/dev/null 2>&1 || \
  /usr/libexec/PlistBuddy -c "Add :NSHighResolutionCapable bool true" "$PLIST" >/dev/null

# Apple documents that script-only apps may otherwise be launched under
# Rosetta as a precaution. Explicitly prefer the native Apple-silicon slice.
/usr/libexec/PlistBuddy -c "Delete :LSArchitecturePriority" "$PLIST" >/dev/null 2>&1 || true
/usr/libexec/PlistBuddy -c "Add :LSArchitecturePriority array" "$PLIST" >/dev/null
/usr/libexec/PlistBuddy -c "Add :LSArchitecturePriority:0 string arm64" "$PLIST" >/dev/null
/usr/libexec/PlistBuddy -c "Add :LSArchitecturePriority:1 string x86_64" "$PLIST" >/dev/null

ICON_INSTALLED=false
if [[ -f "$ICON_SOURCE" ]]; then
  PREVIEW_DIR="$TMP_DIR/preview"
  ICONSET_DIR="$TMP_DIR/GPT-Gateway.iconset"
  mkdir -p "$PREVIEW_DIR" "$ICONSET_DIR"

  # qlmanage, sips, and iconutil are built into macOS.
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
        set_plist_string CFBundleIconFile GPT-Gateway.icns
        ICON_INSTALLED=true
      fi
    fi
  fi
fi

# The app was created locally from source, so clear stale quarantine metadata
# on this generated wrapper only.
/usr/bin/xattr -dr com.apple.quarantine "$APP_DIR" 2>/dev/null || true
/usr/bin/touch "$APP_DIR"

APP_EXEC="$APP_DIR/Contents/MacOS/applet"
ARCH_INFO="$(/usr/bin/file "$APP_EXEC" 2>/dev/null || true)"

printf '\nInstalled: %s\n' "$APP_DIR"
printf 'Proxy default: socks5://127.0.0.1:10808\n'
printf 'Wrapper: native macOS AppleScript applet\n'
printf 'Architecture priority: arm64 -> x86_64\n'
if [[ "$(/usr/bin/uname -m)" == "arm64" ]]; then
  if [[ "$ARCH_INFO" == *"arm64"* ]]; then
    printf 'Apple silicon check: OK (arm64 supported and preferred)\n'
  else
    printf 'Apple silicon check: WARNING - arm64 was not detected in the generated applet\n'
  fi
fi
if [[ "$ICON_INSTALLED" == true ]]; then
  printf 'Custom GPT Gateway icon: installed\n'
else
  printf 'Custom icon: skipped (the launcher still works normally)\n'
fi
printf '\nOpen Finder > Home > Applications and double-click GPT Gateway.\n'
printf 'You can also drag GPT Gateway.app into the Dock.\n\n'
/usr/bin/open "$INSTALL_ROOT"

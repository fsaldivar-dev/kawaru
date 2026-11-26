#!/bin/bash
# Builds build/Kawaru.app.
#   scripts/build.sh          build
#   scripts/build.sh --run      build, then open the app
#   scripts/build.sh --install  build, then copy it to /Applications (needed for the virtual camera)
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN="$(swift build -c release --show-bin-path)/kawaru"

# KAWARU_RELEASE=1 (set by scripts/release.sh) makes the copy for other people: signed for distribution, in its own folder.
RELEASE="${KAWARU_RELEASE:-}"
APP="build/Kawaru.app"
[[ -n "$RELEASE" ]] && APP="build/release/Kawaru.app"
mkdir -p "$(dirname "$APP")"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/kawaru"

# Pictures of the effects, for the gallery (made by scripts/previews.sh).
if compgen -G "assets/efectos/*.jpg" > /dev/null; then
  mkdir -p "$APP/Contents/Resources/efectos"
  cp assets/efectos/*.jpg assets/efectos/*.mp4 "$APP/Contents/Resources/efectos/"
fi

# The networks' logos for the social captions (white on clear; from Simple Icons, CC0).
if compgen -G "assets/redes/*.png" > /dev/null; then
  mkdir -p "$APP/Contents/Resources/redes"
  cp assets/redes/*.png "$APP/Contents/Resources/redes/"
fi

# The illustrated plates behind the wooden and neon captions.
if compgen -G "assets/rotulos/*.png" > /dev/null; then
  mkdir -p "$APP/Contents/Resources/rotulos"
  cp assets/rotulos/*.png "$APP/Contents/Resources/rotulos/"
fi

# The model photos, for showing captions over in the editor.
if [[ -f assets/modelo/persona.png ]]; then
  mkdir -p "$APP/Contents/Resources/modelo"
  for who in persona mujer; do
    [[ -f assets/modelo/$who.png ]] && sips -s format jpeg -s formatOptions 82 assets/modelo/$who.png --out "$APP/Contents/Resources/modelo/$who.jpg" >/dev/null
  done
fi

# Icon: assets/icon_1024.png is the master (an 824 px tile centred on a transparent 1024 px canvas).
if [[ -f assets/icon_1024.png ]]; then
  ICONSET="build/AppIcon.iconset"
  rm -rf "$ICONSET" && mkdir -p "$ICONSET"
  for s in 16 32 128 256 512; do
    sips -z $s $s assets/icon_1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s * 2)) $((s * 2)) assets/icon_1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
  rm -rf "$ICONSET"
fi

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Kawaru</string>
  <key>CFBundleDisplayName</key><string>Kawaru</string>
  <key>CFBundleIdentifier</key><string>dev.kawaru.app</string>
  <key>CFBundleExecutable</key><string>kawaru</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSCameraUsageDescription</key><string>Kawaru mira tu cámara para detectar el sello de manos y cambiarte por un tronco. La imagen no sale de tu Mac ni se guarda.</string>
</dict>
</plist>
PLIST

# Sign with a development certificate when there is one: macOS ties the camera permission to the
# signature, and an ad-hoc signature changes on every build, so the permission would be asked for
# again after each rebuild. Without a certificate it falls back to ad-hoc.
IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | awk '/Apple Development/ {print $2; exit}')"
# For other people's Macs it has to be Developer ID, with the hardened runtime and a timestamp, or Apple will not notarize it.
SIGN_FLAGS=()
if [[ -n "$RELEASE" ]]; then
  IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | awk '/Developer ID Application/ {print $2; exit}')"
  [[ -n "$IDENTITY" ]] || { echo "No hay certificado «Developer ID Application» en el llavero."; exit 1; }
  SIGN_FLAGS=(--options runtime --timestamp)
fi

# The virtual camera is a system extension, and macOS only lets an app install one if the app carries a
# provisioning profile granting it (scripts/provision.sh gets one from Xcode). Without the certificate or
# the profile, the app is built without the extension and works as a preview only.
PROFILES="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
TEAM="" PROFILE=""
if [[ -n "$IDENTITY" ]]; then
  TEAM="$(security find-certificate -a -Z -p 2>/dev/null | awk -v id="$IDENTITY" '
      /^SHA-1 hash:/ {keep = ($3 == id)} keep && /BEGIN CERT/ {on = 1} on {print} /END CERT/ {on = 0}' |
    openssl x509 -noout -subject -nameopt multiline 2>/dev/null | awk -F'= ' '/organizationalUnitName/ {print $2; exit}')"
fi
if [[ -n "$TEAM" && -d "$PROFILES" ]]; then
  TMP="$(mktemp)"
  for f in "$PROFILES"/*.provisionprofile; do
    [[ -e "$f" ]] || continue
    security cms -D -i "$f" > "$TMP" 2>/dev/null || continue
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.application-identifier' "$TMP" 2>/dev/null)" == "$TEAM.dev.kawaru.app" ]] || continue
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.developer.system-extension.install' "$TMP" 2>/dev/null)" == "true" ]] || continue
    # A development profile only covers this developer's Macs; a Developer ID one covers them all. Each build takes its own.
    ALL="$(/usr/libexec/PlistBuddy -c 'Print :ProvisionsAllDevices' "$TMP" 2>/dev/null || true)"
    if [[ -n "$RELEASE" ]]; then [[ "$ALL" == "true" ]] || continue; else [[ "$ALL" != "true" ]] || continue; fi
    PROFILE="$f"
  done
  rm -f "$TMP"
fi

if [[ -n "$PROFILE" ]]; then
  EXT="$APP/Contents/Library/SystemExtensions/dev.kawaru.app.camera.systemextension"
  mkdir -p "$EXT/Contents/MacOS"
  cp "$(dirname "$BIN")/kawaru-camera" "$EXT/Contents/MacOS/kawaru-camera"
  # The version follows the binary, so macOS replaces the installed extension only when its code changed.
  CAMERA_VERSION="$(cksum < "$EXT/Contents/MacOS/kawaru-camera" | cut -d" " -f1)"
  # The Mach service name has to start with one of the extension's app groups, and the group with the team.
  cat > "$EXT/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Kawaru Camera</string>
  <key>CFBundleDisplayName</key><string>Kawaru</string>
  <key>CFBundleIdentifier</key><string>dev.kawaru.app.camera</string>
  <key>CFBundleExecutable</key><string>kawaru-camera</string>
  <key>CFBundlePackageType</key><string>SYSX</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleSupportedPlatforms</key><array><string>MacOSX</string></array>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>$CAMERA_VERSION</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSSystemExtensionUsageDescription</key><string>Kawaru ofrece una cámara virtual para tus videollamadas.</string>
  <key>CMIOExtension</key>
  <dict>
    <key>CMIOExtensionMachServiceName</key><string>$TEAM.dev.kawaru.camera</string>
  </dict>
</dict>
</plist>
PLIST
  ENT="$(mktemp -d)"
  cat > "$ENT/camera.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.app-sandbox</key><true/>
  <key>com.apple.security.application-groups</key><array><string>$TEAM.dev.kawaru</string></array>
</dict>
</plist>
PLIST
  cat > "$ENT/app.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.application-identifier</key><string>$TEAM.dev.kawaru.app</string>
  <key>com.apple.developer.team-identifier</key><string>$TEAM</string>
  <key>com.apple.developer.system-extension.install</key><true/>
  <key>com.apple.security.device.camera</key><true/>
</dict>
</plist>
PLIST
  cp "$PROFILE" "$APP/Contents/embedded.provisionprofile"
  codesign --force --sign "$IDENTITY" ${SIGN_FLAGS[@]+"${SIGN_FLAGS[@]}"} --entitlements "$ENT/camera.plist" --generate-entitlement-der "$EXT" >/dev/null 2>&1
  codesign --force --sign "$IDENTITY" ${SIGN_FLAGS[@]+"${SIGN_FLAGS[@]}"} --entitlements "$ENT/app.plist" --generate-entitlement-der "$APP" >/dev/null 2>&1
  rm -rf "$ENT"
  echo "OK  $APP (con cámara virtual)"
else
  codesign --force --sign "${IDENTITY:--}" "$APP" >/dev/null 2>&1 || codesign --force --sign - "$APP" >/dev/null 2>&1
  echo "OK  $APP (sin cámara virtual: falta el perfil, ver scripts/provision.sh)"
fi

case "${1:-}" in
  --run) open "$APP" ;;
  --install)
    # macOS only installs camera extensions from an app in /Applications.
    pkill -x kawaru 2>/dev/null || true
    # Copied over the old one, never deleted first: removing the app makes macOS uninstall its camera extension.
    ditto "$APP" /Applications/Kawaru.app
    # Only the installed copy may answer to Kawaru's identifier. With the build copy registered as well, the
    # system picked whichever it liked for the app's icon (the camera menu showed a blank one).
    LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
    "$LSREGISTER" -u "$PWD/$APP" >/dev/null 2>&1 || true
    "$LSREGISTER" -f /Applications/Kawaru.app >/dev/null 2>&1 || true
    echo "OK  /Applications/Kawaru.app" ;;
esac

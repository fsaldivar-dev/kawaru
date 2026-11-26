#!/bin/bash
# Gets from Xcode the provisioning profile that lets Kawaru install its camera extension. Run it once
# (and again when the profile expires, a year later). It needs Xcode signed in to your Apple developer
# account and xcodegen (brew install xcodegen).
#
# What it does: builds a throwaway app with Kawaru's bundle identifier and the System Extension capability,
# with automatic signing. Xcode then registers the identifier dev.kawaru.app in your developer account and
# downloads a development profile for it; scripts/build.sh picks the profile up from Xcode's folder.
set -euo pipefail
cd "$(dirname "$0")/.."

IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | awk '/Apple Development/ {print $2; exit}')"
[[ -n "$IDENTITY" ]] || { echo "No hay certificado «Apple Development» en el llavero."; exit 1; }
TEAM="$(security find-certificate -a -Z -p 2>/dev/null | awk -v id="$IDENTITY" '
    /^SHA-1 hash:/ {keep = ($3 == id)} keep && /BEGIN CERT/ {on = 1} on {print} /END CERT/ {on = 0}' |
  openssl x509 -noout -subject -nameopt multiline 2>/dev/null | awk -F'= ' '/organizationalUnitName/ {print $2; exit}')"
[[ -n "$TEAM" ]] || { echo "No se pudo leer el equipo del certificado."; exit 1; }

DIR="build/provision"
rm -rf "$DIR" && mkdir -p "$DIR/Stub"
echo 'import AppKit; NSApplication.shared.run()' > "$DIR/Stub/main.swift"
cat > "$DIR/Stub/Stub.entitlements" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.developer.system-extension.install</key><true/>
</dict>
</plist>
PLIST
cat > "$DIR/project.yml" <<'YML'
name: KawaruProvision
options:
  bundleIdPrefix: dev.kawaru
targets:
  KawaruProvision:
    type: application
    platform: macOS
    deploymentTarget: "14.0"
    sources: [Stub]
    settings:
      PRODUCT_BUNDLE_IDENTIFIER: dev.kawaru.app
      GENERATE_INFOPLIST_FILE: YES
      CODE_SIGN_STYLE: Automatic
      CODE_SIGN_ENTITLEMENTS: Stub/Stub.entitlements
YML
(cd "$DIR" && xcodegen generate --quiet)
xcodebuild -project "$DIR/KawaruProvision.xcodeproj" -scheme KawaruProvision -configuration Debug \
  -derivedDataPath "$DIR/derived" -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
  DEVELOPMENT_TEAM="$TEAM" build | grep -E 'error|warning: .*[Pp]rovision|BUILD' || true
# With --release: also a Developer ID profile, for the copy that goes to other people. Exporting an archive of
# the same throwaway app for "developer-id" makes Xcode create it and leave it in its profiles folder, where
# scripts/release.sh looks for it.
if [[ "${1:-}" == "--release" ]]; then
  xcodebuild -project "$DIR/KawaruProvision.xcodeproj" -scheme KawaruProvision -configuration Release \
    -derivedDataPath "$DIR/derived" -archivePath "$DIR/Kawaru.xcarchive" -allowProvisioningUpdates \
    DEVELOPMENT_TEAM="$TEAM" archive | grep -E 'error|ARCHIVE' || true
  cat > "$DIR/export.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>developer-id</string>
  <key>signingStyle</key><string>automatic</string>
  <key>teamID</key><string>$TEAM</string>
</dict>
</plist>
PLIST
  xcodebuild -exportArchive -archivePath "$DIR/Kawaru.xcarchive" -exportPath "$DIR/export" \
    -exportOptionsPlist "$DIR/export.plist" -allowProvisioningUpdates 2>&1 | grep -E 'error|EXPORT' || true
  # Kept where release.sh looks, in case Xcode did not leave a copy in its own folder.
  if [[ -f "$DIR/export/KawaruProvision.app/Contents/embedded.provisionprofile" ]]; then
    mkdir -p "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
    cp "$DIR/export/KawaruProvision.app/Contents/embedded.provisionprofile" \
       "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles/kawaru-developer-id.provisionprofile"
  fi
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
    -u "$DIR/export/KawaruProvision.app" >/dev/null 2>&1 || true
fi

# The throwaway app shares Kawaru's identifier and has no icon: left registered, the system shows its blank icon
# for Kawaru. Take it out of the register before deleting it.
find "$PWD/$DIR" -name '*.app' -prune -print0 2>/dev/null | while IFS= read -r -d '' made; do
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$made" >/dev/null 2>&1 || true
done
rm -rf "$DIR"
echo "Listo. Ahora: scripts/build.sh --install"

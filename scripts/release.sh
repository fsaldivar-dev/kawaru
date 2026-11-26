#!/bin/bash
# Makes the copy of Kawaru for other people: build/release/Kawaru-<version>.dmg, signed with Developer ID
# and, when the notary credentials are set up, notarized by Apple and stapled.
#
# Once, before the first release:
#   scripts/provision.sh --release                      gets the Developer ID profile from Xcode
#   xcrun notarytool store-credentials kawaru-notary    saves your Apple ID and an app-specific password
#                                                       in the keychain (it asks for them; nothing is kept here)
# Then: scripts/release.sh
# NOTARY_PROFILE names another keychain profile if you saved it under a different name.
set -euo pipefail
cd "$(dirname "$0")/.."
NOTARY="${NOTARY_PROFILE:-kawaru-notary}"

rm -rf build/release && mkdir -p build/release
KAWARU_RELEASE=1 scripts/build.sh | tail -1
APP="build/release/Kawaru.app"
[[ -d "$APP/Contents/Library/SystemExtensions" ]] || { echo "Falta el perfil Developer ID: ejecuta scripts/provision.sh --release"; exit 1; }
codesign --verify --deep --strict "$APP"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
IDENTITY="$(security find-identity -v -p codesigning | awk '/Developer ID Application/ {print $2; exit}')"

# The disk image: the app and a shortcut to Applications to drag it onto.
STAGE="build/release/dmg"
mkdir -p "$STAGE" && ditto "$APP" "$STAGE/Kawaru.app" && ln -s /Applications "$STAGE/Applications"
DMG="build/release/Kawaru-$VERSION.dmg"
hdiutil create -quiet -volname "Kawaru" -srcfolder "$STAGE" -format UDZO -ov "$DMG"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$PWD/$STAGE/Kawaru.app" >/dev/null 2>&1 || true
rm -rf "$STAGE"
codesign --force --sign "$IDENTITY" --timestamp "$DMG"
# Only the installed copy should answer to Kawaru's identifier (see build.sh).
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$PWD/$APP" >/dev/null 2>&1 || true
echo "OK  $DMG (firmado con Developer ID)"

if xcrun notarytool history --keychain-profile "$NOTARY" >/dev/null 2>&1; then
  echo "Enviando a Apple para notarizar (suele tardar unos minutos)..."
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY" --wait | tail -4
  xcrun stapler staple "$DMG" && echo "OK  notarizado y grapado: $DMG"
else
  echo "SIN NOTARIZAR: no hay credenciales guardadas como «$NOTARY»."
  echo "Guárdalas una vez con:  xcrun notarytool store-credentials $NOTARY"
  echo "y vuelve a ejecutar scripts/release.sh. Sin notarizar, otras Mac se negarán a abrir la app."
fi

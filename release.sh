#!/bin/zsh
# Developer ID build, notarized and stapled. Produces build/release/Personal-Ops-Manual-<version>.zip.
#   ./release.sh            build, sign, notarize, staple, zip
#   ./release.sh --install  also replace /Applications/Personal Ops Manual.app with the stapled build
#   ./release.sh --publish  also create the GitHub release v<version> with the zip attached
# Needs: a Developer ID Application certificate in the login Keychain, a notarytool
# Keychain profile (xcrun notarytool store-credentials), and release.env (see below).
set -euo pipefail
cd "$(dirname "$0")"

# Signing identity comes from the environment or a git-ignored release.env next to this script:
#   OPS_TEAM_ID=XXXXXXXXXX   OPS_SIGNING_NAME="Your Name"   OPS_NOTARY_PROFILE=ops-manual-notary
[[ -f release.env ]] && source release.env
TEAM_ID="${OPS_TEAM_ID:?set OPS_TEAM_ID (Apple Team ID)}"
IDENTITY="Developer ID Application: ${OPS_SIGNING_NAME:?set OPS_SIGNING_NAME (name on the certificate)} ($TEAM_ID)"
PROFILE="${OPS_NOTARY_PROFILE:-ops-manual-notary}"
VERSION=$(sed -n 's/^ *MARKETING_VERSION: "\(.*\)"/\1/p' project.yml | head -1)
OUT="build/release"
APP="build/Build/Products/Release/Personal Ops Manual.app"
ZIP="$OUT/Personal-Ops-Manual-$VERSION.zip"

xcodegen generate
xcodebuild -project OpsManual.xcodeproj -scheme OpsManual -configuration Release \
  -derivedDataPath build build -quiet \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$IDENTITY" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  ENABLE_HARDENED_RUNTIME=YES \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  ENABLE_DEBUG_DYLIB=NO \
  OTHER_CODE_SIGN_FLAGS="--timestamp"

codesign --verify --deep --strict --verbose=2 "$APP"
mkdir -p "$OUT"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "Submitting to Apple notary service…"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$APP"
spctl --assess --type execute --verbose=2 "$APP"

# Re-zip with the ticket stapled so the download is the stapled app.
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
echo "Release artifact: $ZIP"

for arg in "$@"; do
  case "$arg" in
    --install)
      if [[ -d "/Applications/Personal Ops Manual.app" ]]; then
        mv "/Applications/Personal Ops Manual.app" "$HOME/.Trash/Personal Ops Manual $(date +%Y%m%d-%H%M%S).app"
      fi
      ditto "$APP" "/Applications/Personal Ops Manual.app"
      # Only the installed copy may be known to LaunchServices: stray build products
      # with the same bundle id are what make the Dock show a stale icon.
      LSREG=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
      "$LSREG" -u "$APP" >/dev/null 2>&1 || true
      rm -rf "build/Build/Products/Debug/Personal Ops Manual.app" "$HOME/Library/Developer/Xcode/DerivedData"/OpsManual-*/Build/Products/*/"Personal Ops Manual.app" 2>/dev/null || true
      "$LSREG" -f -R "/Applications/Personal Ops Manual.app" >/dev/null 2>&1 || true
      rm -rf "$HOME/Library/Caches/com.apple.iconservices.store" 2>/dev/null || true
      killall Dock 2>/dev/null || true
      echo "Installed to /Applications (build copies unregistered, Dock refreshed)"
      ;;
    --publish)
      gh release create "v$VERSION" "$ZIP" --title "Personal Ops Manual $VERSION" \
        --notes "Notarized Developer ID build. Unzip and drop into /Applications. macOS 26 or newer." \
        || echo "gh release create failed (does v$VERSION already exist?)"
      ;;
  esac
done

#!/bin/zsh
# Release build, ad hoc signed. `./build.sh --install` also copies to /Applications.
set -euo pipefail
cd "$(dirname "$0")"
xcodegen generate
xcodebuild -project OpsManual.xcodeproj -scheme OpsManual -configuration Release \
  -derivedDataPath build CODE_SIGN_IDENTITY="-" build -quiet
APP="build/Build/Products/Release/Personal Ops Manual.app"
codesign --force --deep --sign - "$APP"
echo "Built: $APP"
if [[ "${1:-}" == "--install" ]]; then
  if [[ -e "/Applications/Personal Ops Manual.app" ]]; then
    ASIDE="$HOME/.Trash/Personal Ops Manual $(date +%Y%m%d-%H%M%S).app"
    mv "/Applications/Personal Ops Manual.app" "$ASIDE"
    echo "Moved the previous bundle to: $ASIDE"
  fi
  ditto "$APP" "/Applications/Personal Ops Manual.app"
  LSREG=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
  "$LSREG" -u "$APP" >/dev/null 2>&1 || true
  "$LSREG" -f -R "/Applications/Personal Ops Manual.app" >/dev/null 2>&1 || true
  killall Dock 2>/dev/null || true
  echo "Installed to /Applications (build copy unregistered, Dock refreshed)"
fi

#!/bin/sh
# Assembles Annotated.app. Signs with the identity ./sign-identity.sh makes, so
# the Accessibility grant survives a rebuild; without it the signature is
# ad-hoc, whose designated requirement is a cdhash that every build changes.
# CODESIGN_IDENTITY overrides.
set -e
cd "$(dirname "$0")"

swift build -c release
.build/release/Annotated --self-check

APP="Annotated.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Annotated "$APP/Contents/MacOS/Annotated"
cp Info.plist "$APP/Contents/Info.plist"
cp Resources/Annotated.icns "$APP/Contents/Resources/Annotated.icns"
SELF_SIGNED="Annotated Self-Signed"
if [ -z "$CODESIGN_IDENTITY" ]; then
  if security find-identity -v -p codesigning | grep -q "$SELF_SIGNED"; then
    CODESIGN_IDENTITY="$SELF_SIGNED"
  else
    CODESIGN_IDENTITY="-"
    echo "warning: no signing identity, falling back to ad-hoc — the"
    echo "         Accessibility grant will not survive this build."
    echo "         Run ./sign-identity.sh once to fix that."
  fi
fi
codesign --force --sign "$CODESIGN_IDENTITY" "$APP"

echo "built $PWD/$APP (signed: $CODESIGN_IDENTITY)"

# INSTALL=1 replaces the copy in /Applications — the one that owns the login
# item. Without it a rebuild leaves that copy stale.
if [ -n "$INSTALL" ]; then
  rm -rf "/Applications/Annotated.app"
  cp -R "$APP" /Applications/
  echo "installed /Applications/Annotated.app"
fi

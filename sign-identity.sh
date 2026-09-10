#!/bin/sh
# Creates the self-signed code-signing identity build.sh looks for. Run once.
#
# An ad-hoc signature's designated requirement is its cdhash, so every rebuild
# is a different app as far as TCC is concerned and the Accessibility grant has
# to be given again. A signing identity makes the requirement the certificate
# instead, which survives rebuilds: grant once and it sticks.
set -e
NAME="Annotated Self-Signed"

if security find-identity -v -p codesigning | grep -q "$NAME"; then
  echo "identity \"$NAME\" already exists"
  exit 0
fi

DIR="$(mktemp -d)"
trap 'rm -rf "$DIR"' EXIT

openssl req -x509 -newkey rsa:2048 -keyout "$DIR/key.pem" -out "$DIR/cert.pem" \
  -days 7300 -nodes -subj "/CN=$NAME" \
  -addext "basicConstraints=critical,CA:false" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning" 2>/dev/null
openssl pkcs12 -export -inkey "$DIR/key.pem" -in "$DIR/cert.pem" \
  -out "$DIR/id.p12" -passout pass: -name "$NAME"

KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
security import "$DIR/id.p12" -k "$KEYCHAIN" -P "" -T /usr/bin/codesign -A
# codesign refuses a certificate it cannot build a trusted chain for.
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$DIR/cert.pem"

security find-identity -v -p codesigning | grep "$NAME"
echo "identity ready — now run: INSTALL=1 ./build.sh"

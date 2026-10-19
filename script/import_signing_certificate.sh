#!/usr/bin/env bash
# Usage: script/import_signing_certificate.sh
# Puts the Developer ID certificate into a temporary keychain on a CI runner.
# Does nothing without BEAMMAC_SIGN_P12_BASE64, so unsigned builds keep working.
#   BEAMMAC_SIGN_P12_BASE64    base64 of the .p12 export (certificate and key)
#   BEAMMAC_SIGN_P12_PASSWORD  password of the .p12
set -euo pipefail

if [[ -z "${BEAMMAC_SIGN_P12_BASE64:-}" ]]; then
  echo "Kein Zertifikat gesetzt, die App wird ad-hoc signiert"
  exit 0
fi
: "${BEAMMAC_SIGN_P12_PASSWORD:?BEAMMAC_SIGN_P12_PASSWORD fehlt}"

tmp="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
keychain="$tmp/beammac-signing.keychain-db"
keychain_password="$(uuidgen)"
p12="$tmp/beammac-signing.p12"
trap 'rm -f "$p12"' EXIT

printf '%s' "$BEAMMAC_SIGN_P12_BASE64" | base64 --decode >"$p12"
security create-keychain -p "$keychain_password" "$keychain"
# Locks again after six hours, so a hung job does not leave the key open.
security set-keychain-settings -lut 21600 "$keychain"
security unlock-keychain -p "$keychain_password" "$keychain"
security import "$p12" -k "$keychain" -P "$BEAMMAC_SIGN_P12_PASSWORD" -T /usr/bin/codesign
# Lets codesign use the key without a dialog on the headless runner.
security set-key-partition-list -S apple-tool:,apple: -s -k "$keychain_password" "$keychain" >/dev/null
security list-keychains -d user -s "$keychain" login.keychain-db
security find-identity -v -p codesigning "$keychain" | grep -q "Developer ID Application" ||
  { echo "Im Zertifikat steckt keine Developer ID Application" >&2; exit 1; }

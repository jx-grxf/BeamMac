#!/usr/bin/env bash
# Usage: script/set_signing_secrets.sh <DeveloperID.p12> <issuer-id>
# Stores the Developer ID certificate and the App Store Connect API key as
# secrets of the GitHub "release" environment, which only v* tags can use.
# Export the .p12 in Keychain Access: right-click "Developer ID Application"
# → Export, with a password. The script asks for that password.
set -euo pipefail

p12="${1:?Pfad zur .p12 fehlt}"
issuer="${2:?Issuer-ID aus App Store Connect (Benutzer und Zugriff → Integrationen) fehlt}"
repo="jx-grxf/BeamMac"
env_name="release"

[[ -f "$p12" ]] || { echo "$p12 gibt es nicht" >&2; exit 1; }
read -rsp "Passwort der .p12: " password
echo

identity="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)"
[[ -n "$identity" ]] || { echo "Keine Developer ID Application im Schlüsselbund" >&2; exit 1; }

key_file="$(find "$HOME/.appstoreconnect/private_keys" -name 'AuthKey_*.p8' 2>/dev/null | head -1)"
[[ -n "$key_file" ]] || { echo "Kein AuthKey_*.p8 in ~/.appstoreconnect/private_keys" >&2; exit 1; }
key_id="$(basename "$key_file" .p8)"
key_id="${key_id#AuthKey_}"

set_secret() { gh secret set "$1" --repo "$repo" --env "$env_name" --body "$2" >/dev/null; echo "gesetzt: $1"; }
set_secret BEAMMAC_SIGN_IDENTITY "$identity"
set_secret BEAMMAC_SIGN_P12_BASE64 "$(base64 -i "$p12")"
set_secret BEAMMAC_SIGN_P12_PASSWORD "$password"
set_secret BEAMMAC_NOTARY_KEY_ID "$key_id"
set_secret BEAMMAC_NOTARY_ISSUER_ID "$issuer"
set_secret BEAMMAC_NOTARY_KEY_P8_BASE64 "$(base64 -i "$key_file")"
echo "Fertig. Lösch die .p12 jetzt: rm \"$p12\""

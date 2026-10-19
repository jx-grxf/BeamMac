#!/usr/bin/env bash
# Usage: script/notarize.sh dist/BeamMac-<version>.dmg
# Sends the DMG to Apple's notary service and staples the ticket.
# Credentials, first match wins:
#   BEAMMAC_NOTARY_KEYCHAIN_PROFILE              a profile from notarytool store-credentials
#   BEAMMAC_NOTARY_KEY_ID + BEAMMAC_NOTARY_ISSUER_ID and
#   BEAMMAC_NOTARY_KEY_PATH or BEAMMAC_NOTARY_KEY_P8_BASE64   App Store Connect API key
set -euo pipefail

dmg="${1:?DMG fehlt}"
[[ -f "$dmg" ]] || { echo "$dmg gibt es nicht" >&2; exit 1; }

if [[ -n "${BEAMMAC_NOTARY_KEYCHAIN_PROFILE:-}" ]]; then
  auth=(--keychain-profile "$BEAMMAC_NOTARY_KEYCHAIN_PROFILE")
else
  : "${BEAMMAC_NOTARY_KEY_ID:?BEAMMAC_NOTARY_KEY_ID fehlt}"
  : "${BEAMMAC_NOTARY_ISSUER_ID:?BEAMMAC_NOTARY_ISSUER_ID fehlt}"
  key="${BEAMMAC_NOTARY_KEY_PATH:-}"
  if [[ -z "$key" ]]; then
    : "${BEAMMAC_NOTARY_KEY_P8_BASE64:?Schlüssel fehlt: BEAMMAC_NOTARY_KEY_PATH oder BEAMMAC_NOTARY_KEY_P8_BASE64}"
    key_dir="$(mktemp -d)"
    trap 'rm -rf "$key_dir"' EXIT
    key="$key_dir/AuthKey_$BEAMMAC_NOTARY_KEY_ID.p8"
    printf '%s' "$BEAMMAC_NOTARY_KEY_P8_BASE64" | base64 --decode >"$key"
  fi
  auth=(--key "$key" --key-id "$BEAMMAC_NOTARY_KEY_ID" --issuer "$BEAMMAC_NOTARY_ISSUER_ID")
fi

xcrun notarytool submit "$dmg" "${auth[@]}" --wait
xcrun stapler staple "$dmg"
xcrun stapler validate "$dmg"
spctl --assess --type open --context context:primary-signature -v "$dmg"

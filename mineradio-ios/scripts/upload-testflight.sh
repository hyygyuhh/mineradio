#!/usr/bin/env bash
# Uploads the built IPA to TestFlight using an App Store Connect API key.
set -euo pipefail

: "${APP_STORE_CONNECT_API_KEY_ID:?need secret}"
: "${APP_STORE_CONNECT_ISSUER_ID:?need secret}"
: "${APP_STORE_CONNECT_API_KEY_BASE64:?need secret}"

IOS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IPA="$(ls "$IOS_DIR"/build/ipa/*.ipa 2>/dev/null | head -n1 || true)"
if [[ -z "$IPA" ]]; then
  echo "[upload-testflight] no IPA found in build/ipa" >&2
  exit 1
fi

KEY_DIR="$HOME/private_keys"
mkdir -p "$KEY_DIR"
KEY_PATH="$KEY_DIR/AuthKey_$APP_STORE_CONNECT_API_KEY_ID.p8"
echo "$APP_STORE_CONNECT_API_KEY_BASE64" | base64 -D -o "$KEY_PATH"

echo "[upload-testflight] uploading $IPA"
xcrun altool \
  --upload-app \
  --type ios \
  --file "$IPA" \
  --apiKey "$APP_STORE_CONNECT_API_KEY_ID" \
  --apiIssuer "$APP_STORE_CONNECT_ISSUER_ID"

#!/usr/bin/env bash
# Imports the iOS signing certificate + provisioning profile from base64
# secrets into a temporary keychain. Run on a CI macOS runner.
set -euo pipefail

KEYCHAIN_PASSWORD="${IOS_KEYCHAIN_PASSWORD:-ci-$(date +%s)}"
KEYCHAIN_PATH="$HOME/ci.keychain"

echo "[import-certs] creating keychain $KEYCHAIN_PATH"
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH" || true
security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"

CERT_PATH="$HOME/dev.p12"
echo "$IOS_CERTIFICATE_BASE64" | base64 -D -o "$CERT_PATH"
echo "[import-certs] importing certificate…"
security import "$CERT_PATH" -P "$IOS_P12_PASSWORD" -A -t cert -k "$KEYCHAIN_PATH" || true
rm -f "$CERT_PATH"

security list-keychains -d user -s "$KEYCHAIN_PATH" login.keychain
security set-key-partition-list -S apple-tool:,apple: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH" || true

# Provisioning profile.
PROFILE_DIR="$HOME/Library/MobileDevice/Provisioning Profiles"
mkdir -p "$PROFILE_DIR"
PROFILE_RAW="$HOME/dev.mobileprovision"
echo "$IOS_PROVISION_PROFILE_BASE64" | base64 -D -o "$PROFILE_RAW"
UUID="$(/usr/libexec/PlistBuddy -c 'Print UUID' /dev/stdin <<< \
  "$(security cms -D -i "$PROFILE_RAW")")"
echo "[import-certs] installing profile $UUID"
cp "$PROFILE_RAW" "$PROFILE_DIR/$UUID.mobileprovision"
rm -f "$PROFILE_RAW"

#!/usr/bin/env bash
# Cloud / local build for mineradio-ios.
#
#   ./mineradio-ios/scripts/ci-build.sh simulator   # simulator smoke test (default)
#   ./mineradio-ios/scripts/ci-build.sh ipa         # signed IPA (needs secrets)
#   ./mineradio-ios/scripts/ci-build.sh testflight  # IPA + upload to TestFlight
#
# Requires macOS + Xcode. Installs XcodeGen on demand via Homebrew.
set -euo pipefail

MODE="${1:-simulator}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IOS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$IOS_DIR"

echo "[ci-build] mode=$MODE"
echo "[ci-build] syncing Bridge assets…"
bash "$SCRIPT_DIR/sync-bridge.sh"

echo "[ci-build] ensuring XcodeGen…"
if ! command -v xcodegen >/dev/null 2>&1; then
  if ! command -v brew >/dev/null 2>&1; then
    echo "[ci-build] Homebrew not found; install XcodeGen manually." >&2
    exit 1
  fi
  brew install xcodegen
fi

echo "[ci-build] generating Xcode project…"
xcodegen generate

case "$MODE" in
  simulator)
    echo "[ci-build] simulator smoke test…"
    mkdir -p build
    set -x
    xcodebuild \
      -project MineRadioWeb.xcodeproj \
      -scheme MineRadioWeb \
      -destination "generic/platform=iOS Simulator" \
      -configuration Debug \
      -derivedDataPath build \
      build \
      CODE_SIGNING_ALLOWED=NO
    ;;
  ipa|testflight)
    : "${IOS_TEAM_ID:?need secret IOS_TEAM_ID}"
    : "${IOS_CODE_SIGN_IDENTITY:?need secret IOS_CODE_SIGN_IDENTITY}"
    : "${IOS_PROVISIONING_PROFILE_NAME:?need secret IOS_PROVISIONING_PROFILE_NAME}"
    : "${IOS_CERTIFICATE_BASE64:?need secret IOS_CERTIFICATE_BASE64}"
    : "${IOS_P12_PASSWORD:?need secret IOS_P12_PASSWORD}"
    : "${IOS_PROVISION_PROFILE_BASE64:?need secret IOS_PROVISION_PROFILE_BASE64}"

    export IOS_TEAM_ID IOS_CODE_SIGN_IDENTITY IOS_PROVISIONING_PROFILE_NAME \
           IOS_CERTIFICATE_BASE64 IOS_P12_PASSWORD IOS_PROVISION_PROFILE_BASE64
    bash "$SCRIPT_DIR/import-certs.sh" || true

    ARCHIVE_PATH="$IOS_DIR/build/Mineradio.xcarchive"
    IPA_DIR="$IOS_DIR/build/ipa"
    mkdir -p "$IPA_DIR"

    echo "[ci-build] archiving…"
    set -x
    xcodebuild \
      -project MineRadioWeb.xcodeproj \
      -scheme MineRadioWeb \
      -configuration Release \
      -sdk iphoneos \
      -destination "generic/platform=iOS" \
      -archivePath "$ARCHIVE_PATH" \
      -derivedDataPath "$IOS_DIR/build" \
      archive \
      DEVELOPMENT_TEAM="$IOS_TEAM_ID" \
      CODE_SIGN_IDENTITY="$IOS_CODE_SIGN_IDENTITY" \
      PROVISIONING_PROFILE_SPECIFIER="$IOS_PROVISIONING_PROFILE_NAME"

    echo "[ci-build] exporting IPA…"
    cat > "$IOS_DIR/build/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>app-store</string>
  <key>teamID</key>
  <string>$IOS_TEAM_ID</string>
  <key>uploadSymbols</key>
  <true/>
</dict>
</plist>
EOF
    xcodebuild \
      -exportArchive \
      -archivePath "$ARCHIVE_PATH" \
      -exportOptionsPlist "$IOS_DIR/build/ExportOptions.plist" \
      -exportPath "$IPA_DIR"
    ;;
  *)
    echo "[ci-build] unknown mode: $MODE (use simulator|ipa|testflight)" >&2
    exit 1
    ;;
esac

if [[ "$MODE" == "testflight" ]]; then
  : "${APP_STORE_CONNECT_API_KEY_ID:?need secret}"
  : "${APP_STORE_CONNECT_ISSUER_ID:?need secret}"
  : "${APP_STORE_CONNECT_API_KEY_BASE64:?need secret}"
  export APP_STORE_CONNECT_API_KEY_ID APP_STORE_CONNECT_ISSUER_ID APP_STORE_CONNECT_API_KEY_BASE64
  bash "$SCRIPT_DIR/upload-testflight.sh"
fi

echo "[ci-build] done."

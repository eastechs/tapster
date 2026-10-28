#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Textend Dev"
APP_BUNDLE="$ROOT_DIR/build/Build/Products/Debug/$APP_NAME.app"
case "$MODE" in
  run|--debug|--logs|--telemetry|--verify|--build-only|--preview|--initialize-cloudkit-schema|--setup-development-signing) ;;
  *) echo "usage: $0 [--debug|--logs|--telemetry|--verify|--build-only|--preview|--initialize-cloudkit-schema|--setup-development-signing]" >&2; exit 2 ;;
esac

if [[ "$MODE" == "--preview" || "$MODE" == "--initialize-cloudkit-schema" ]] && pgrep -f -x "$APP_BUNDLE/Contents/MacOS/$APP_NAME( .*)?" >/dev/null; then
  echo "The development preview is already running. Quit it before rebuilding; the installed release can remain open." >&2
  exit 1
fi
if [[ "$MODE" != "--build-only" ]] && pgrep -x "$APP_NAME" >/dev/null; then
  echo "Textend Dev is already running. Reuse that preview, or quit it before rebuilding." >&2
  exit 1
fi
if [[ "$MODE" == "--setup-development-signing" ]]; then
  # Explicit one-time setup through the account signed in to Xcode. This registers
  # only the development App ID; production signing remains manually provisioned.
  xcodebuild -quiet -project "$ROOT_DIR/Textend.xcodeproj" -scheme Textend \
    -configuration Debug -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath "$ROOT_DIR/build" \
    -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
    CODE_SIGN_STYLE=Automatic TEXTEND_PROVISIONING_PROFILE= build
fi
SIGNING_VALUES="$(python3 "$ROOT_DIR/script/provisioning.py" development)"
IFS=$'\t' read -r PROFILE_UUID LOCAL_SIGNING_IDENTITY SIGNING_TEAM SIGNING_STYLE <<< "$SIGNING_VALUES"
if [[ "$SIGNING_STYLE" == "Automatic" ]]; then
  # Xcode-managed profiles cannot be selected as manually managed profiles.
  PROFILE_UUID=""
  LOCAL_SIGNING_IDENTITY="Apple Development"
fi
xcodebuild -quiet -project "$ROOT_DIR/Textend.xcodeproj" -scheme Textend \
  -configuration Debug -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath "$ROOT_DIR/build" \
  CODE_SIGN_STYLE="$SIGNING_STYLE" TEXTEND_SIGNING_IDENTITY="$LOCAL_SIGNING_IDENTITY" DEVELOPMENT_TEAM="$SIGNING_TEAM" \
  TEXTEND_PROVISIONING_PROFILE="$PROFILE_UUID" build
python3 "$ROOT_DIR/script/provisioning.py" development --verify-app "$APP_BUNDLE" >/dev/null

# Login-item or external launches can occur during the build. Do not let -n
# create a second process sharing the development store and menu bar icon.
if [[ "$MODE" == "--preview" || "$MODE" == "--initialize-cloudkit-schema" ]] && pgrep -f -x "$APP_BUNDLE/Contents/MacOS/$APP_NAME( .*)?" >/dev/null; then
  echo "Textend started during the build. Reuse that process, or quit it before launching an isolated preview." >&2
  exit 1
fi

case "$MODE" in
  --build-only|--setup-development-signing) echo "$APP_BUNDLE" ;;
  --initialize-cloudkit-schema) open -n "$APP_BUNDLE" --args --sync-preview --initialize-cloudkit-schema ;;
  --preview) open -n "$APP_BUNDLE" --args --sync-preview ;;
  --debug) lldb -- "$APP_BUNDLE/Contents/MacOS/$APP_NAME" ;;
  --logs) open "$APP_BUNDLE"; /usr/bin/log stream --info --style compact --predicate 'process == "Textend Dev"' ;;
  --telemetry) open "$APP_BUNDLE"; /usr/bin/log stream --info --style compact --predicate 'subsystem == "chat.eastechs.textend.debug"' ;;
  --verify) open "$APP_BUNDLE"; sleep 1; pgrep -x "$APP_NAME" >/dev/null; echo "$APP_NAME is running." ;;
  run) open "$APP_BUNDLE" ;;
esac

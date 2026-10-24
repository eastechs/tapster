#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Textend"
APP_BUNDLE="$ROOT_DIR/build/Build/Products/Debug/$APP_NAME.app"
case "$MODE" in
  run|--debug|--logs|--telemetry|--verify|--build-only) ;;
  *) echo "usage: $0 [--debug|--logs|--telemetry|--verify|--build-only]" >&2; exit 2 ;;
esac

if [[ "$MODE" != "--build-only" ]]; then
  # Stop the pre-rename development build too, so only one expander runs.
  pkill -x "Tapster" >/dev/null 2>&1 || true
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
fi
LOCAL_SIGNING_IDENTITY="${TEXTEND_SIGNING_IDENTITY:-${TAPSTER_SIGNING_IDENTITY:-}}"
if [[ -z "$LOCAL_SIGNING_IDENTITY" ]]; then
  LOCAL_SIGNING_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | awk '/"Apple Development:/{print $2; exit}')"
fi
LOCAL_SIGNING_IDENTITY="${LOCAL_SIGNING_IDENTITY:--}"
xcodebuild -quiet -project "$ROOT_DIR/Tapster.xcodeproj" -scheme Tapster \
  -configuration Debug -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath "$ROOT_DIR/build" \
  CODE_SIGN_IDENTITY="$LOCAL_SIGNING_IDENTITY" build

case "$MODE" in
  --build-only) echo "$APP_BUNDLE" ;;
  --debug) lldb -- "$APP_BUNDLE/Contents/MacOS/$APP_NAME" ;;
  --logs) open "$APP_BUNDLE"; /usr/bin/log stream --info --style compact --predicate 'process == "Textend"' ;;
  --telemetry) open "$APP_BUNDLE"; /usr/bin/log stream --info --style compact --predicate 'subsystem == "chat.eastechs.tapster"' ;;
  --verify) open "$APP_BUNDLE"; sleep 1; pgrep -x "$APP_NAME" >/dev/null; echo "$APP_NAME is running." ;;
  run) open "$APP_BUNDLE" ;;
esac

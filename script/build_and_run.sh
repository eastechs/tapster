#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Textend"
APP_BUNDLE="$ROOT_DIR/build/Build/Products/Debug/$APP_NAME.app"
case "$MODE" in
  run|--debug|--logs|--telemetry|--verify|--build-only|--preview|--initialize-cloudkit-schema) ;;
  *) echo "usage: $0 [--debug|--logs|--telemetry|--verify|--build-only|--preview|--initialize-cloudkit-schema]" >&2; exit 2 ;;
esac

if [[ "$MODE" == "--preview" || "$MODE" == "--initialize-cloudkit-schema" ]] && pgrep -f -x "$APP_BUNDLE/Contents/MacOS/$APP_NAME( --sync-preview)?" >/dev/null; then
  echo "The development preview is already running. Quit it before rebuilding; the installed release can remain open." >&2
  exit 1
fi
SIGNING_VALUES="$(python3 "$ROOT_DIR/script/provisioning.py" development)"
IFS=$'\t' read -r PROFILE_UUID LOCAL_SIGNING_IDENTITY SIGNING_TEAM <<< "$SIGNING_VALUES"
if [[ "$MODE" != "--build-only" && "$MODE" != "--preview" && "$MODE" != "--initialize-cloudkit-schema" ]]; then
  if pgrep -x "$APP_NAME" >/dev/null; then
    echo "Textend is already running. Quit it first, or use --preview to inspect an isolated development library without expansion." >&2
    exit 1
  fi
fi
xcodebuild -quiet -project "$ROOT_DIR/Tapster.xcodeproj" -scheme Tapster \
  -configuration Debug -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath "$ROOT_DIR/build" \
  CODE_SIGN_IDENTITY="$LOCAL_SIGNING_IDENTITY" DEVELOPMENT_TEAM="$SIGNING_TEAM" \
  PROVISIONING_PROFILE_SPECIFIER="$PROFILE_UUID" build

case "$MODE" in
  --build-only) echo "$APP_BUNDLE" ;;
  --initialize-cloudkit-schema) open -n "$APP_BUNDLE" --args --sync-preview --initialize-cloudkit-schema ;;
  --preview) open -n "$APP_BUNDLE" --args --sync-preview ;;
  --debug) lldb -- "$APP_BUNDLE/Contents/MacOS/$APP_NAME" ;;
  --logs) open "$APP_BUNDLE"; /usr/bin/log stream --info --style compact --predicate 'process == "Textend"' ;;
  --telemetry) open "$APP_BUNDLE"; /usr/bin/log stream --info --style compact --predicate 'subsystem == "chat.eastechs.tapster"' ;;
  --verify) open "$APP_BUNDLE"; sleep 1; pgrep -x "$APP_NAME" >/dev/null; echo "$APP_NAME is running." ;;
  run) open "$APP_BUNDLE" ;;
esac

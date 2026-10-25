#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEVELOPER_DIR_PATH="$(xcode-select -p)"
ICON_TOOL="$DEVELOPER_DIR_PATH/../Applications/Icon Composer.app/Contents/Executables/ictool"
if [[ ! -x "$ICON_TOOL" ]]; then
  echo "Icon Composer's export tool was not found in the selected Xcode installation." >&2
  exit 1
fi
"$ICON_TOOL" "$ROOT_DIR/Textend/Resources/Textend.icon" --export-image \
  --output-file "$ROOT_DIR/docs/design/textend/Textend.png" \
  --platform macOS --rendition Default --width 1024 --height 1024 --scale 1 --design-generation 27

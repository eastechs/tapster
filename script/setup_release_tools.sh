#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOLS_ENV="$ROOT_DIR/.build/release-tools"
python3 -m venv "$TOOLS_ENV"
"$TOOLS_ENV/bin/python" -m pip install -r "$ROOT_DIR/script/requirements-release.txt"
"$TOOLS_ENV/bin/aws" --version

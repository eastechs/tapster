#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
bash -n script/build_and_run.sh script/check.sh script/export_icon.sh script/setup_release_tools.sh
git diff --check
swift format lint --strict --recursive Tapster Tests Package.swift
python3 script/test_release.py
swift test
./script/build_and_run.sh --build-only

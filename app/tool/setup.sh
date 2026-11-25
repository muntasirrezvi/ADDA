#!/usr/bin/env bash
# Creates the Android/iOS project files (first time only) and applies Adda's native settings.
# Run from the app folder:  bash tool/setup.sh
set -euo pipefail
cd "$(dirname "$0")/.."
if [ ! -d android ] || [ ! -d ios ]; then
  flutter create --org app.adda --project-name adda --platforms android,ios .
  rm -f test/widget_test.dart
fi
python3 tool/patch_native.py
echo "Native setup done."

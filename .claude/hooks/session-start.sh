#!/bin/bash
set -euo pipefail

# Only run in Claude Code cloud sessions
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

FLUTTER_DIR="$HOME/flutter"
if [ ! -x "$FLUTTER_DIR/bin/flutter" ]; then
  git clone --depth 1 -b stable https://github.com/flutter/flutter.git "$FLUTTER_DIR"
fi
export PATH="$FLUTTER_DIR/bin:$PATH"
echo "export PATH=\"$FLUTTER_DIR/bin:\$PATH\"" >> "${CLAUDE_ENV_FILE:-/dev/null}"

flutter config --no-analytics >/dev/null 2>&1 || true
cd "$CLAUDE_PROJECT_DIR"
flutter pub get

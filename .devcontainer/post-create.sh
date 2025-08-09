#!/usr/bin/env bash
set -e

# Ensure flutter is on PATH for the vscode user session
echo 'export PATH="/usr/local/flutter/bin:/usr/local/flutter/bin/cache/dart-sdk/bin:$PATH"' >> /home/vscode/.bashrc

# Precache common artifacts (web)
/usr/local/flutter/bin/flutter precache --web || true

# run flutter doctor to show issues
/usr/local/flutter/bin/flutter doctor -v || true

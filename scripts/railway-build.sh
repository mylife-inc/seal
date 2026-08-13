#!/usr/bin/env bash
set -euo pipefail

# BEGIN SGIT MANAGED BLOCK
cleanup() {
  if command -v sgit >/dev/null 2>&1; then
    sgit clean || true
  fi
}
trap cleanup EXIT
if ! command -v sgit >/dev/null 2>&1; then
  curl -fsSL "https://raw.githubusercontent.com/mylife-inc/releases/main/codeseal/install.sh" -o /tmp/install-sgit.sh
  SGIT_ONLY=1 sh /tmp/install-sgit.sh
fi
sgit run-secure -- docker build -t app .
# END SGIT MANAGED BLOCK

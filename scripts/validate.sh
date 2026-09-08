#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "AUTO Xray repository validation"
echo "==============================="

VERSION="$(tr -d '[:space:]' < VERSION)"
[ -n "$VERSION" ] || { echo "VERSION is empty"; exit 1; }

echo "Version: $VERSION"

echo "Checking Ruby helper..."
ruby -c src/auto-xray-helper.rb

echo "Checking shell scripts..."
for f in scripts/*.sh; do
  bash -n "$f"
done

echo "Checking for accidental private data..."
if grep -RInE --exclude-dir=.git --exclude='validate.sh' \
  '(subscription_url\.txt|hwid\.txt|runtime_config\.json|proxy_state\.json|AUTO_XRAY_RUNTIME\.log|vless://[^[:space:]]+)' \
  .; then
  echo
  echo "Potential private/runtime data found. Review before committing."
  exit 1
fi

echo "Checking generated/runtime files are not committed..."
for p in \
  'vless-work' \
  'runtime_config.json' \
  'proxy_state.json' \
  'nodes.json' \
  'subscription_url.txt' \
  'hwid.txt'; do
  if git ls-files | grep -E "(^|/)${p//./\.}($|/)" >/dev/null 2>&1; then
    echo "Runtime/private path is tracked: $p"
    exit 1
  fi
done

echo "OK"

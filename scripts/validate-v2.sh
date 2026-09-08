#!/usr/bin/env bash
set -euo pipefail

printf 'AUTO Xray repository validation\n'
printf '===============================\n'

VERSION="$(tr -d '[:space:]' < VERSION)"
printf 'Version: %s\n' "$VERSION"

printf 'Checking Ruby helper...\n'
ruby -c src/auto-xray-helper.rb

printf 'Checking shell scripts...\n'
while IFS= read -r -d '' f; do
  bash -n "$f"
done < <(find scripts -type f -name '*.sh' -print0)

printf 'Checking tracked runtime/private files...\n'
forbidden_tracked_regex='(^|/)(subscription_url\.txt|hwid\.txt|runtime_config\.json|proxy_state\.json|xray\.pid|AUTO_XRAY_RUNTIME\.log|nodes\.json|vless-links\.txt|DUPLICATES\.txt|SUMMARY\.txt)$'
if git ls-files | grep -E "$forbidden_tracked_regex" >/tmp/auto-xray-forbidden-files.txt; then
  cat /tmp/auto-xray-forbidden-files.txt
  echo
  echo 'Runtime/private files must not be tracked.'
  exit 1
fi

printf 'Checking source for obvious embedded secrets...\n'
secret_patterns=(
  'vless://[0-9a-fA-F]{8}-[0-9a-fA-F-]{27,}@'
  'x-hwid:[[:space:]]*[0-9a-fA-F-]{20,}'
  '"privateKey"[[:space:]]*:[[:space:]]*"[^"[:space:]]{16,}"'
  '"publicKey"[[:space:]]*:[[:space:]]*"[^"[:space:]]{16,}"'
)

for pattern in "${secret_patterns[@]}"; do
  if git grep -nEI "$pattern" -- ':!docs/**' ':!README.md' ':!SECURITY.md' ':!GITHUB_RELEASE_TEXT.md' ':!MAINTAINER_PUBLISHING.md' ':!vendor/**' > /tmp/auto-xray-secret-hits.txt; then
    cat /tmp/auto-xray-secret-hits.txt
    echo
    echo 'Potential embedded secret found. Review before committing.'
    exit 1
  fi
done

printf 'Checking for local user paths...\n'
if git grep -nE '/Users/[^/$][^/]*/' -- ':!docs/**' ':!README.md' ':!MAINTAINER_PUBLISHING.md' > /tmp/auto-xray-userpaths.txt; then
  cat /tmp/auto-xray-userpaths.txt
  echo
  echo 'User-specific absolute macOS path found.'
  exit 1
fi

printf 'Validation OK.\n'

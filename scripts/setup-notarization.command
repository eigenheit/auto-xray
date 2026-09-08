#!/bin/bash
set -euo pipefail

PROFILE="AUTO-Xray-notary"
/usr/bin/xcrun notarytool --version >/dev/null 2>&1 || { echo "notarytool не найден."; exit 20; }

read -r -p "Apple ID email: " APPLE_ID
read -r -p "Team ID: " TEAM_ID
read -r -s -p "App-specific password: " APP_PASSWORD
printf '\n'

/usr/bin/xcrun notarytool store-credentials "$PROFILE" \
  --apple-id "$APPLE_ID" \
  --team-id "$TEAM_ID" \
  --password "$APP_PASSWORD"

unset APP_PASSWORD

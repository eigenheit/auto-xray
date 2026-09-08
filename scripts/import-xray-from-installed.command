#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

EXPECTED_SHA="25ab858d6a6d763c3bf98d21a9c26571a58d807a857b273e49d6b824c4cb4f39"
DEST="vendor/xray/xray"
mkdir -p "vendor/xray"

CANDIDATES=(
  "$HOME/Applications/AUTO Xray.app/Contents/Resources/xray"
  "/Applications/AUTO Xray.app/Contents/Resources/xray"
  "/Applications/V2RayXS.app/Contents/Resources/xray"
  "/Applications/V2RayXS.app/Contents/MacOS/xray"
)

SRC=""
for C in "${CANDIDATES[@]}"; do
  if [ -x "$C" ]; then
    VER="$($C version 2>&1 || true)"
    if echo "$VER" | /usr/bin/grep -q "Xray 1.8.4"; then
      SHA="$(/usr/bin/shasum -a 256 "$C" | /usr/bin/awk '{print $1}')"
      if [ "$SHA" = "$EXPECTED_SHA" ]; then
        SRC="$C"
        break
      fi
    fi
  fi
done

if [ -z "$SRC" ]; then
  echo "Не найден проверенный Xray-core 1.8.4."
  echo "Ожидаемый SHA-256: $EXPECTED_SHA"
  echo
  echo "Если AUTO Xray v2.3+ уже установлен, убедитесь, что приложение находится в Applications."
  exit 20
fi

cp "$SRC" "$DEST"
chmod +x "$DEST"
echo "Imported: $SRC"
echo "To:       $DEST"

# AUTO Xray — development and release flow

This document is for maintainers. End users should follow `README.md` and `docs/INSTALLATION.md`.

## Repository layout

```text
src/
  AUTO_Xray.applescript
  auto-xray-helper.rb
scripts/
  build-catalina.sh
  validate.sh
vendor/
  README.md
  XRAY_VERSION.txt
  XRAY_SHA256.txt
assets/
  dove-icon.png
```

The Xray executable is intentionally not committed to Git. Public release assets may bundle it, but source control only records its expected version and SHA-256.

## Validation

Run from the repository root:

```bash
bash scripts/validate.sh
```

GitHub Actions runs the same validation automatically on pull requests and pushes to `main`.

## Catalina build

The final compatibility build must be produced on the tested Intel Catalina Mac.

Provide the verified Xray 1.8.4 binary either at:

```text
vendor/xray
```

or through:

```bash
XRAY_BIN=/path/to/xray bash scripts/build-catalina.sh
```

The script verifies the binary SHA-256 before packaging it.

Expected output on the Catalina Mac:

```text
~/Desktop/AUTO_Xray_<version>_BUILD/
  AUTO Xray.app
  AUTO_Xray_Catalina_Intel_v<version>_LOCAL.dmg
  AUTO_Xray_v<version>_Catalina_App_for_Signing.zip
```

The local DMG uses an ad-hoc signature and is for testing only.

## Public release

Until Developer ID signing/notarization is enabled, publish two user paths:

1. DMG for normal drag-to-Applications installation.
2. Catalina fallback installer ZIP for users blocked by Gatekeeper.

Always publish SHA-256 checksums with release assets.

Do not publish subscription URLs, HWIDs, runtime configuration, logs, generated node databases, or personal paths.

## Versioning

`VERSION` is the single repository version source. New release work should update it before building.

Use semantic release tags such as:

```text
v2.5.1
v2.6.0
```

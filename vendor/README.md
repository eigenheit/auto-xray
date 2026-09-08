# Xray-core binary

The repository does **not** track the Xray executable itself.

AUTO Xray public releases bundle a Catalina-compatible Intel build of **Xray-core 1.8.4**.

Expected binary metadata:

- platform: `darwin/amd64`
- version: `1.8.4`
- SHA-256: see `XRAY_SHA256.txt`

For a local Catalina build, either:

1. place the verified executable at `vendor/xray`, or
2. set `XRAY_BIN=/absolute/path/to/xray` when running `scripts/build-catalina.sh`.

The build script refuses to package a binary whose SHA-256 differs from `XRAY_SHA256.txt`.

Licensing information for Xray-core is documented in the repository root `THIRD_PARTY_NOTICES.txt`.

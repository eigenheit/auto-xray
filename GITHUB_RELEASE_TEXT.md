# AUTO Xray 2.5.20 — Stable

Lightweight standalone VLESS/Reality client for older Intel Macs running macOS Catalina.

## Support

- Intel Mac (`x86_64`)
- tested on macOS Catalina 10.15.x
- no V2RayXS required
- no Python installation required
- bundled Xray-core 1.8.4

## Download

**Recommended:**

`AUTO_Xray_Catalina_v2.5.20.dmg`

Open the DMG and launch **Install AUTO Xray.app** using `Control-click → Open`.

If Catalina initially shows a warning without an **Open** button, click **Cancel**, then repeat `Control-click → Open` and confirm **Open** on the second prompt.

**Fallback ZIP installer:**

`AUTO_Xray_Catalina_Installer_v2.5.20.zip`

Extract the archive and launch `INSTALL_AUTO_XRAY_CATALINA.command`.

After installation, AUTO Xray starts in the **OFF** state.

## macOS Gatekeeper

AUTO Xray may be distributed without Apple Developer ID signing/notarization, so Catalina can report that the developer cannot be verified.

Use only the standard macOS one-time exception described above or:

`System Preferences → Security & Privacy → General → Open Anyway`

Do not disable Gatekeeper globally.

Full guide: `docs/INSTALLATION.md`.

## First run

🕊 → **Update subscription** → paste your HTTPS VLESS subscription URL → choose RF / EU / World → **Enable**.

Telegram Desktop:

`Settings → Advanced → Connection type → Proxy settings → Use system proxy settings`

## Release integrity

Each public release includes `SHA256SUMS.txt`. Verify downloaded files against the published SHA-256 values before troubleshooting suspicious download warnings.

Do not publish subscription URLs, UUIDs, Reality keys, HWIDs, tokens, or passwords in Issues.

Documentation: `README.md` · Russian README: `README.ru.md`.

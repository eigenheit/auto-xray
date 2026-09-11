# Security

**English** · [Русский](SECURITY.ru.md)

## Download only from the official release

Use only the **GitHub Releases** section of this repository.

Do not run copies of AUTO Xray obtained from unknown Telegram channels, file-sharing services, or third-party websites.

## Gatekeeper

AUTO Xray may currently be distributed without an Apple Developer ID signature and notarization. macOS Catalina may therefore warn that the developer cannot be verified.

If you downloaded the release yourself from the official GitHub repository and the checksum matches, use the standard one-time macOS exception:

- `Control-click → Open`;
- or **Security & Privacy → Open Anyway**.

Apple Support: https://support.apple.com/102445

We **do not recommend disabling Gatekeeper globally**.

Do not use this command to install AUTO Xray:

```text
sudo spctl --master-disable
```

and do not change global macOS security settings unless necessary.

## When NOT to bypass a warning

Do not run the file if macOS reports that:

- the app “will damage your computer”;
- malware was detected;
- the app was automatically moved to Trash;
- the SHA-256 does not match the published value;
- the archive or app was modified after download.

Download a fresh copy from the official release instead.

## Checksums

Public releases include `SHA256SUMS.txt`.

On macOS, verify a file with:

```bash
shasum -a 256 /path/to/file
```

The resulting value must exactly match the value published in the GitHub Release.

## Private data

Do not publish the following in Issues:

- VLESS subscription URLs;
- UUIDs;
- Reality keys;
- tokens;
- passwords;
- HWIDs.

Review logs before posting them and remove any private data.

## Third-party component

AUTO Xray includes Xray-core 1.8.4.

Third-party licensing information is provided in:

```text
THIRD_PARTY_NOTICES.txt
```

# AUTO Xray — FAQ

**English** · [Русский](FAQ.ru.md)

## Which Macs is AUTO Xray intended for?

The tested configuration is an **Intel Mac (`x86_64`) running macOS Catalina 10.15.x**.

AUTO Xray was created specifically as a lightweight client for older Intel Macs where modern VLESS/VPN clients already require a newer macOS version.

## Does AUTO Xray work on Apple Silicon?

The current release is not intended for M1/M2/M3/M4 Macs. It bundles the Intel build of Xray-core.

## Why does macOS say the developer cannot be verified?

The public build is not currently signed with an Apple Developer ID and is not notarized.

On Catalina, the tested flow is:

1. `Control-click → Open` on **Install AUTO Xray.app**.
2. If the first warning does not contain an **Open** button, click **Cancel**.
3. Repeat `Control-click → Open`.
4. The second warning should show **Open** — click it.

Do not disable Gatekeeper globally.

## Do I need to install Xray separately?

No. The tested **Xray-core 1.8.4** is already included in the installation package.

## Do I need V2RayXS?

No. AUTO Xray is a standalone client.

If V2RayXS or another local proxy client is running, it is best to quit it before the first AUTO Xray installation.

## Which local ports does AUTO Xray use?

- HTTP/HTTPS: `127.0.0.1:9001`
- SOCKS5: `127.0.0.1:2081`

## Is this a full-device VPN?

AUTO Xray uses the macOS system proxy settings. It is not a TUN/Network Extension VPN.

Most applications that use the system proxy will work through AUTO Xray. Applications that ignore the macOS system proxy may connect directly.

## How should I configure Telegram?

In Telegram Desktop:

**Settings → Advanced → Connection type → Proxy settings → Use system proxy settings**

You do not need to enter a separate SOCKS port.

## What do RF / EU / World mean?

They are groups of nodes from your subscription. In automatic mode, AUTO Xray passes the group to Xray and uses `leastPing` to select the available node with the best latency within that group.

## What happens if Wi-Fi disconnects?

The AUTO Xray supervisor periodically checks proxy availability. After Wi-Fi returns, it reapplies the system proxy settings and restarts Xray if necessary.

## What happens when AUTO Xray is disabled?

AUTO Xray stops Xray and restores the previous macOS proxy settings.

If the previous configuration pointed to a non-working local proxy, AUTO Xray disables that stale localhost proxy so normal internet access is not lost.

## Where are settings stored?

```text
~/Library/Application Support/AUTO Xray/
```

Logs:

```text
~/Library/Logs/AUTO Xray/
```

## Is the subscription preserved during updates?

Yes. The installer preserves the subscription URL, HWID, and working settings.

## What should I do if AUTO Xray does not start?

Start with [INSTALLATION.md](INSTALLATION.md), then see [TROUBLESHOOTING.md](TROUBLESHOOTING.md).

If you create a GitHub Issue, do not publish subscription URLs, UUIDs, Reality keys, HWIDs, or passwords.

## Can I trust the downloaded file?

Download only from the official GitHub Releases page. Every release publishes `SHA256SUMS.txt`.

If macOS says **“will damage your computer”**, detects malware, or moves the file to Trash as malicious software, do not bypass the warning.

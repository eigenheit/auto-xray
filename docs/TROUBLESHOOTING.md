# AUTO Xray — troubleshooting

**English** · [Русский](TROUBLESHOOTING.ru.md)

## 1. The dove 🕊 does not appear

Open the app manually:

```text
Applications → AUTO Xray
```

If you used the alternative Catalina Installer, the app may be located here:

```text
~/Applications/AUTO Xray.app
```

If macOS blocks the app, follow the installation guide:

[INSTALLATION.md](INSTALLATION.md)

---

## 2. The dove is visible, but the internet does not work

1. Click 🕊.
2. Choose **Disable**.
3. Wait a few seconds.
4. Click **Enable** again.

Quit V2RayXS completely, along with any other apps that modify the macOS system proxy themselves.

AUTO Xray uses these local ports:

```text
HTTP/HTTPS: 127.0.0.1:9001
SOCKS5:     127.0.0.1:2081
```

Two proxy clients changing system settings at the same time may interfere with each other.

---

## 3. The subscription does not update

Check that:

- the URL starts with `https://`;
- it is actually a VLESS subscription URL;
- the internet works while AUTO Xray is disabled;
- the subscription has not expired;
- your provider has not limited the number of devices.

Try again using:

**🕊 → Update subscription**

Do not publish your subscription URL in a GitHub Issue.

---

## 4. Telegram does not connect

In Telegram Desktop:

**Settings → Advanced → Connection type → Proxy settings**

choose:

**Use system proxy settings**

If you previously used V2RayXS, remove or do not select the old proxy:

```text
SOCKS5 127.0.0.1:1081
```

AUTO Xray uses a different local SOCKS port:

```text
127.0.0.1:2081
```

However, when **Use system proxy settings** is enabled, you do not need to enter this port manually in Telegram.

---

## 5. macOS says “developer cannot be verified”

This is a Gatekeeper warning.

Do not disable Gatekeeper.

Use either:

- `Control-click → Open`;
- or, on Catalina:
  **System Preferences → Security & Privacy → General → Open Anyway**.

Full instructions:

[INSTALLATION.md](INSTALLATION.md)

---

## 6. macOS says the app “will damage your computer”

Do not bypass this warning.

1. Delete the downloaded file.
2. Download the release again from the official GitHub page.
3. Verify the SHA-256 checksum if one is published.
4. If the warning appears again, create an Issue and do not launch the app.

---

## 7. macOS says “app is damaged”

Do not use random commands from the internet to disable macOS security protections.

First:

1. delete the DMG/ZIP;
2. download the release again;
3. extract it using the standard macOS **Archive Utility**;
4. verify the checksum;
5. try the alternative Catalina Installer.

A “damaged” message may also indicate that the downloaded file was corrupted or modified.

---

## 8. The installer shows `Permission denied`

This applies to the alternative `.command` installer.

Open Terminal and type:

```text
chmod +x 
```

leaving the trailing space.

Drag `INSTALL_AUTO_XRAY_CATALINA.command` into the Terminal window and press `Enter`.

Then try launching the installer again.

---

## 9. AUTO Xray is enabled, but a specific website does not open

Try switching groups:

- **Auto · RF**
- **Auto · EU**
- **Auto · World**

or select a different server manually.

Some websites may be unavailable from a particular country or network.

---

## 10. Where to find the log

AUTO Xray logs:

```text
~/Library/Logs/AUTO Xray/
```

Working data:

```text
~/Library/Application Support/AUTO Xray/
```

When asking for help, you may share the latest log lines, but first make sure they do not contain a private subscription URL, UUID, or keys.

---

## 11. How to completely remove AUTO Xray

Use:

```text
UNINSTALL_AUTO_XRAY.command
```

If this file is not present in your release, create an Issue and include the version number.

---

## What to include in a GitHub Issue

Include:

- Mac model;
- Intel or Apple Silicon;
- macOS version;
- AUTO Xray version;
- installation method: DMG or Catalina Installer;
- exact error text;
- what happened immediately before the error.

Do not publish:

- subscription URLs;
- UUIDs;
- Reality public/private keys;
- passwords;
- personal access tokens.

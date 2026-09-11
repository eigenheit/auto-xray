# Installing AUTO Xray on an older Mac

**English** · [Русский](INSTALLATION.ru.md)

This guide is written for users who are not experienced with Terminal.

## Before installation

Check the following:

- your Mac must use an **Intel** processor;
- the tested system version is **macOS Catalina 10.15.x**;
- the old V2RayXS app is not required for AUTO Xray;
- Python does not need to be installed.

If V2RayXS or another local proxy/VPN client is already running, it is best to quit it completely before the first AUTO Xray launch.

---

# Method 1. DMG — recommended

Download from **GitHub Releases**:

```text
AUTO_Xray_Catalina_v2.5.20.dmg
```

1. Double-click the DMG.
2. In the window that opens, find **Install AUTO Xray.app**.
3. `Control-click` it and choose **Open**.
4. On macOS Catalina, the first system warning may say that the developer cannot be verified and may **not show an Open button**. Usually only **Move to Trash** and **Cancel** are available in this first dialog.
5. Click **Cancel** and close the warning.
6. `Control-click` **Install AUTO Xray.app** again and choose **Open** again.
7. A second system warning should appear, this time with an **Open** button. Click it.
8. Installation starts automatically and does not require additional AUTO Xray confirmations.
9. When installation is complete, a dove 🕊 appears in the menu bar. AUTO Xray starts in the **OFF** state and normal internet access should continue directly.

This two-step Gatekeeper behavior was tested on a real Intel Mac running macOS Catalina.

---

# macOS says the developer cannot be verified

AUTO Xray is currently distributed without an Apple Developer ID signature or notarization, so Catalina may show an unknown-developer warning.

Use only the normal macOS mechanisms described below.

## Main method on Catalina

1. `Control-click` **Install AUTO Xray.app**.
2. Choose **Open**.
3. If the first warning does not contain an **Open** button, click **Cancel**.
4. Repeat `Control-click → Open`.
5. In the second warning, click **Open**.

After a successful first launch, macOS normally remembers this decision for that version of the app.

## If repeating Control-click → Open does not help

On Catalina:

1. Try opening **Install AUTO Xray.app** once and close the warning.
2. Open ** → System Preferences**.
3. Open **Security & Privacy**.
4. Go to the **General** tab.
5. If settings are locked, click the lock and enter your Mac user password.
6. Find the message about blocked **Install AUTO Xray.app**.
7. Click **Open Anyway**.
8. Confirm **Open**.

On newer macOS versions:

**System Settings → Privacy & Security → Security → Open Anyway**

Apple provides this as a standard one-time exception for an app from an unidentified developer.

---

# Method 2. Fallback ZIP installer for Catalina

If the DMG cannot be opened or the app keeps getting blocked, use:

```text
AUTO_Xray_Catalina_Installer_v2.5.20.zip
```

1. Download the ZIP only from this project's GitHub Releases page.
2. Double-click the ZIP — macOS will extract it.
3. Open the extracted folder.
4. Find:

```text
INSTALL_AUTO_XRAY_CATALINA.command
```

5. Prefer launching it with `Control-click → Open`.
6. A Terminal window will open. The installer will create AUTO Xray locally on your Mac.
7. When installation finishes, the app will be available at:

```text
~/Applications/AUTO Xray.app
```

and will launch automatically.

This method does not download Xray-core and does not require V2RayXS to be installed first.

## If the .command file does not start

If macOS shows an unidentified-developer warning, use the same standard **Open / Open Anyway** steps described above.

If Terminal shows only:

```text
Permission denied
```

then the file has lost its executable permission.

Do the following:

1. Open **Terminal**.
2. Type:

```text
chmod +x 
```

Make sure to leave a space after `+x`.

3. Drag `INSTALL_AUTO_XRAY_CATALINA.command` from Finder into the Terminal window.
4. Press `Enter`.
5. Try launching the installer again.

---

# Which warnings can be allowed, and which must not be bypassed

## You may continue if you downloaded the file from the official GitHub Releases page

Typical messages include:

- “developer cannot be verified”;
- “Apple cannot check it for malicious software”;
- “the application was downloaded from the Internet”.

In these cases, use **Open / Open Anyway** as described above.

## Do not continue if macOS says

- **“will damage your computer”**;
- malware was detected;
- the file was automatically moved to Trash specifically as malicious software;
- the downloaded file's SHA-256 does not match the published value.

Delete the downloaded file and obtain a new copy from the official release.

Do not disable Gatekeeper globally and do not use `spctl --master-disable`.

---

# First launch of AUTO Xray

After installation, the dove 🕊 should be translucent — this is the **OFF** state.

Click the dove:

1. **Update subscription**
2. paste the HTTPS URL of your VLESS subscription
3. choose RF / EU / World
4. click **Enable**

A bright dove means AUTO Xray is enabled.

---

# Telegram

In Telegram Desktop:

**Settings → Advanced → Connection type → Proxy settings → Use system proxy settings**

Do not select the old V2RayXS SOCKS proxy at `127.0.0.1:1081`.

---

# If installation still does not work

See:

[TROUBLESHOOTING.md](TROUBLESHOOTING.md)

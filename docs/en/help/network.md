---
title: Networking and proxy
description: Where to set the proxy, what address format to use, how the connection test works, and what to do when the sign-in page won't load.
---

# Networking and proxy

**Language / 语言:** [中文](/help/network.md) · English

## Where do I set the proxy?

Open **Settings → Proxy**. There is a single field: **HTTP proxy address**.

## What do I type?

The format is `host:port`, for example:

```
127.0.0.1:7890
http://127.0.0.1:7890
```

Notes:

- **The port is not fixed**: use the **HTTP or Mixed port** shown by your proxy app (Clash and similar tools display it on the main screen or in settings).
- **`127.0.0.1` means "the proxy runs on this device"**: use it when the proxy app and DAViewer are on the same phone or PC. To let a phone use a proxy running on your PC, enter the PC's LAN IP (e.g. `192.168.x.x`) and enable "allow LAN connections" in the proxy app.
- Only **HTTP proxies** are supported (most tools' HTTP/Mixed ports qualify). No SOCKS, and no usernames/passwords in the address.

## The three buttons

- **Save and test**: saves the address and immediately tests whether DeviantArt is reachable — the recommended way.
- **Test DeviantArt connection**: tests the current settings without changing anything.
- **Restore auto-detect**: clears the manual proxy and returns to auto-detection (system proxy and environment variables); it re-probes immediately.

A successful test means all app traffic — API, images, downloads, and the sign-in page — now goes through this path. The test covers only the app's own traffic; it does **not** change how your browser works.

## What does the startup message mean?

On launch you may briefly see "Checking DeviantArt connectivity…":

- Direct or proxied connection OK → all good, nothing to do.
- Unreachable → set a proxy as above or check your network; details are in **Settings → Diagnostics**.

## The sign-in page won't load / is blank / stuck

1. Make sure the proxy app is running and the port is right; tap "Test DeviantArt connection".
2. Blank or stuck page: tap **refresh in the top-right corner** of the sign-in page.
3. A notice mentioning "Max challenge attempts exceeded" means the network tripped DeviantArt's protection: **wait 1–2 minutes and refresh once** — don't refresh repeatedly.
4. macOS 12/13 special case: the in-app test may pass while the sign-in page still needs the **system proxy** (System Settings → Network → Proxies).

## Reporting a network problem

**Settings → Diagnostics** shows runtime logs. The export button in its top bar bundles the last 20 launches into one redacted file, and "Report a problem" opens a prefilled GitHub issue — the fastest way to give the developer what they need.

## Technical details

Per-platform proxy mechanics (WebView2, WKWebsiteDataStore, environment-variable precedence) and the maintainer checklist live in [Networking and proxy internals](/en/networking.md) — not needed for everyday use.

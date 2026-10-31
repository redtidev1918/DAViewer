---
title: FAQ
description: Quick fixes for the most common sign-in, loading, mature-content, and update questions.
---

# FAQ

**Language / 语言:** [中文](/help/faq.md) · English

## The sign-in page won't load or gets stuck

Close and reopen it. If it persists, check the proxy in **Settings → Proxy** and run "Test DeviantArt connection". See [Networking and proxy](network.md).

## The page asks for a CAPTCHA or account confirmation

That's DeviantArt's own security check. Complete it on the page — the app waits and nothing is interrupted.

## "Recommendations need recovery", but Daily Deviations work

Recommendations depend on the website session; Daily Deviations don't. Follow the notice to sign in again — details in [Login and account](login-and-account.md).

## Mature content is hidden or blurred

DAViewer follows your DeviantArt account preferences; there is no in-app override. Go to **Settings → DeviantArt account settings → Mature content settings** (opens deviantart.com), make sure "show mature content" is on and age verification is complete, then refresh the app.

## macOS asks for Keychain permission

Click "Allow" — DAViewer stores your credentials in the system keychain. Choose "Always Allow" to stop being asked every time. This is macOS's normal security mechanism, not a fault.

## I want to switch accounts

**Log out first, then sign in** with the new account (Settings → Logout). Don't switch accounts via cookie import — it only accepts cookies of the currently signed-in account.

## How do I update the app?

- When a new version is out, a "New version available" banner appears above the home feed — tap it to read the notes, then "Download" to open the releases page.
- Or check manually: **Settings → Check for updates**.
- Very old versions (Android 0.5.10 and earlier) should download the new package from the releases page and install it over the old one.

## Images load slowly / spin forever

1. Check [Networking and proxy](network.md); configure a proxy if needed.
2. Pull down to refresh the list.
3. **Settings → Clear cache**, then reopen the page (thumbnails re-download; sign-in and favourites are unaffected).

## I hid something by mistake

Settings → **Content filters** — tap "Unhide" next to the entry. It returns to your lists instantly, no re-downloading needed. See [Content filters](/en/content-filtering.md).

## Still stuck?

**Settings → Diagnostics**: view logs, export the last 20 launches (redacted automatically), or tap "Report a problem" to jump to a prefilled GitHub issue.

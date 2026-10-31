---
title: Login and account
description: How to sign in, why the app sometimes asks you to sign in again, cookie import/export, and mature-content settings.
---

# Login and account

**Language / 语言:** [中文](/help/login-and-account.md) · English

## How do I sign in?

Tap **Login** (shown in the top-right corner while signed out) and complete sign-in on the official DeviantArt page that opens inside the app.

- All sign-in, registration, password recovery, and provider logins (Google, Apple, …) happen on that official page; DAViewer has no separate "social login".
- Complete any CAPTCHA as prompted — the app waits for you.
- One sign-in does two things at once: account authorization and the app's internal website session. After that, recommendations, watching, favourites, and notifications all work.

## Why is the feed still empty after signing in?

The "For You" feed needs a valid website session. Sometimes the app shows you as signed in while the feed's sign-in state has expired. Try in order:

1. **Pull down to refresh** the feed once.
2. Check your connection — make sure [deviantart.com](https://www.deviantart.com) opens on this device; if you need a proxy see [Networking and proxy](network.md).
3. Open **Settings → Login status** and tap the check button in both cards ("Recommendations & browsing" and "Watching, favourites & notifications"), then follow the prompts.
4. Still stuck? Sign in again: **Settings → Logout**, then **Login**.

> Don't worry: signing in again **never deletes** your DeviantArt favourites or watches — they live in your account. Images already downloaded to this device are untouched too.

## What do the "session expired" notices mean?

Two kinds, with different fixes:

- **Web session expired; recommendations and other web features are limited** → tap **Sign in again** on the notice, or re-login from Settings.
- **App authorization expired** → tap **Re-authorize** and go through sign-in once more.

Neither affects content you've favourited or downloaded.

## Sign out / switch accounts

- Sign out: **Settings → Logout** (also signs out the in-app website session).
- Switch accounts: **log out first, then sign in** with the new account. Cookie import refuses mixed accounts.

## View, export, and import cookies

A cookie is the website's "login ticket" — DAViewer uses it to act as you on DeviantArt's web features. Entry point: **Settings → Account cookies**:

- **View/copy**: shows the current cookies as JSON; "Copy cookies (JSON)" copies them to the clipboard so you can back them up.
- **Import**: tap "Import cookies". Three formats are accepted — JSON exported by this app, cookie arrays from browser extensions, or raw `name=value; name=value` header text.
- Imported cookies must belong to the **same account** that's currently signed in; anonymous cookies or a mismatched username are rejected. After a successful import the app may offer a passwordless confirmation dialog — you can just dismiss it.

## Mature content

DAViewer doesn't have its own mature-content switch; it follows your DeviantArt account preferences: **Settings → DeviantArt account settings → Mature content settings** (opens the matching page on deviantart.com). Change it there, then refresh the app.

## Technical details

The full authentication and session-recovery mechanics (error policy, recovery transaction, cold-start contract) live in [Authentication and session recovery](/en/authentication.md) — you don't need it for everyday use.

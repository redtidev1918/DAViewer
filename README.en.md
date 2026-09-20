# DAViewer

<p align="center">
  <img src="assets/icon/icon.png" alt="DAViewer" width="160" />
</p>

**Language:** English · [中文](README.md)

[![Docs](https://img.shields.io/badge/Docs-文档站点-6366f1?style=flat-square)](https://redtidev1918.github.io/DAViewer/)

DeviantArt has discontinued its official client app. DAViewer is an
open-source DeviantArt client built on
[DAKit](https://github.com/redtidev1918/DAKit), providing the website's core
features as a native app for Android, macOS, and Windows.

[![GitHub stars](https://img.shields.io/github/stars/redtidev1918/DAViewer?style=flat&color=yellow)](https://github.com/redtidev1918/DAViewer/stargazers)
[![GitHub license](https://img.shields.io/github/license/redtidev1918/DAViewer?style=flat)](LICENSE)
[![GitHub release](https://img.shields.io/github/v/release/redtidev1918/DAViewer?style=flat)](https://github.com/redtidev1918/DAViewer/releases)
[![Platforms](https://img.shields.io/badge/platform-Android%20%7C%20macOS%20%7C%20Windows-blue?style=flat)](https://github.com/redtidev1918/DAViewer/releases)
[![Flutter](https://img.shields.io/badge/Flutter-3.47.1-blue?style=flat&logo=flutter)](https://flutter.dev)

## Install

Download the package for your platform from
[Releases](https://github.com/redtidev1918/DAViewer/releases):

- **Android**: `DAViewer-v<version>.apk`
- **Windows**: `DAViewer-v<version>-windows.zip` — unzip and run `DAViewer.exe`.
  Sign-in happens entirely inside the app: no system settings touched, no
  administrator rights, runs from anywhere
- **macOS 12+**: `DAViewer-v<version>-macos-unsigned-preview.zip` — universal
  Intel and Apple Silicon build; unzip and drag to Applications

macOS blocks the first launch: this is a free community preview without an
Apple signature. Right-click the app icon in Finder and choose **Open** — it
runs normally after that, and the app never uploads or collects any data.

## Screenshots

<table align="center">
  <tr>
    <td align="center"><img src="docs/screenshots/home_feed.jpg" width="200" /><br /><sub>Home feed</sub></td>
    <td align="center"><img src="docs/screenshots/artwork_detail.jpg" width="200" /><br /><sub>Artwork detail</sub></td>
    <td align="center"><img src="docs/screenshots/related_works.jpg" width="200" /><br /><sub>Related works</sub></td>
  </tr>
</table>

## Contents

- [Why](#why)
- [Features](#features)
- [Relationship with DAKit](#relationship-with-dakit)
- [References & acknowledgements](#references--acknowledgements)
- [Before you start](#before-you-start)
- [Run](#run)
- [Proxy](#proxy)
- [Build & release](#build--release)
- [Home & sign-in state](#home--sign-in-state)
- [Login FAQ](#login-faq)
- [Contributing](#contributing)
- [Notes](#notes)

## Why

- DeviantArt has discontinued its official client app;
- The website has rich functionality (recommendations, galleries,
  tags, favourites, watch, download) but no native desktop/mobile experience;
- This project combines the website's core features with native interaction,
  out of the box — no need to register your own OAuth app.

## Features

- **Sign in**: one "Sign in or create an account" action opens DeviantArt's
  official login page in the app's embedded WebView; choose DeviantArt, Google,
  Apple, or Facebook right on that page. One login establishes both the OAuth
  session and the web session (personalized feed, collections)
- **Recommendations**: Home “For you” is the website's personalized
  `rfy/deviations` feed (web Cookie + CSRF), matching the site's recommendations
- **Search**: live search (results as you type) + compact tag-style history +
  paste a DeviantArt link to jump straight to an artwork or artist; “Recommended
  for you” and popular tags show an artwork preview (Pixiv style)
- **Artwork detail**: swipe or top-bar buttons to browse previous/next works
  (adjacent images prefetched); pinch zoom; paged multi-image works; publish and
  update times shown under the title as auto-refreshing relative timestamps
- **Media**: shared image zoom; highest-quality video that autoplays and loops,
  with seeking and retry; GIF badge + cached rich-text images with loading progress
- **Related content**: native "More like this", similar artists,
  featured/suggested collections (openable in full), and "More from this
  artist" on the detail page, with clear empty and failure states
- **Tags**: one compact tag row across detail, search, and tag screens, with
  automatic tag hydration from official metadata; tag pages sort by Newest or
  Popular
- **Artist**: profile (including bio, watcher count, join date), gallery with
  keyword search over their own works, custom sub-galleries (folders),
  favourites, watch
- **Sharing**: native system sharing for artwork, artists, gallery folders,
  favourite collections, and tags; artwork links can still be copied separately
- **Social**: favourite (with state), watch/unwatch, watched-user list,
  notifications (unread dot + local mark-as-read)
- **Download**: real-time original-file permission check; thumbnail previews;
  explains login, purchase, quota, or creator restrictions and falls back to the
  highest-quality preview; long-press an image to download that page (with
  confirmation) and get a completion toast with the saved location; open
  file/folder and delete confirmation
- **Appearance & settings**: light / dark / system theme; persisted language and
  theme; clear cache; check for updates
- **Update reminders**: a slim dismissible Home banner when a newer version is
  available — tap it to read what's new before deciding to download; ignored
  versions never nag again — no modals, no auto-download
- **Problem reporting**: Diagnostics generates a pre-filled GitHub issue (with
  an optional redacted log); the app collects and uploads nothing
- **Bilingual**: Chinese / English toggle
- **Proxy**: auto-detect the system proxy + manual configuration (required in
  mainland China)

## Relationship with DAKit

`DAViewer` is the app; DAKit is the SDK. The client only depends on published
DAKit packages and does not copy SDK code: OAuth, official API mapping, domain
models, and background transfers live in DAKit; generic private-website protocol
parsing lives in the optional `dakit_web` package; WebView sessions, capability
routing, and native interaction live in DAViewer. Dependencies:

```yaml
dependencies:
  dakit_core: ^1.1.0
  dakit_api: ^1.0.0
  dakit_flutter: ^1.0.0
  dakit_web: ^0.2.1
```

Each attempt creates one official OAuth/PKCE transaction. Account selection,
passwords, and provider security checks stay on DeviantArt's official page inside
the app's embedded WebView. After the callback, every feature uses that one
OAuth identity plus the WebView's web session; there is no second web sign-in to
synchronize. Signed-out state is onboarding, not a feed error. See
[Architecture](docs/en/architecture.md) for the full boundaries.

## References & acknowledgements

DAViewer is built on these open-source projects:

- **[DAKit](https://github.com/redtidev1918/DAKit)** — the DeviantArt SDK this app
  uses (OAuth, official API mapping, domain models, background transfers),
  published on pub.dev; docs:
  [DAKit documentation](https://github.com/redtidev1918/DAKit#documentation)
- **[Flutter](https://flutter.dev)** — the cross-platform UI framework
- **[flutter_inappwebview](https://pub.dev/packages/flutter_inappwebview)** — embedded
  WebView (sign-in, web adapters)
- **[flutter_riverpod](https://pub.dev/packages/flutter_riverpod)** — state management
- **[go_router](https://pub.dev/packages/go_router)** — routing
- **[dio](https://pub.dev/packages/dio)** — HTTP client
- **[cached_network_image](https://pub.dev/packages/cached_network_image)** /
  **[flutter_cache_manager](https://pub.dev/packages/flutter_cache_manager)** — image caching
- **[flutter_secure_storage](https://pub.dev/packages/flutter_secure_storage)** — secure
  storage for the sign-in token
- **[share_plus](https://pub.dev/packages/share_plus)** — native share sheet
- **[url_launcher](https://pub.dev/packages/url_launcher)** — opening external links
- **[path_provider](https://pub.dev/packages/path_provider)** — local paths
- **[chewie](https://pub.dev/packages/chewie)** / **[video_player](https://pub.dev/packages/video_player)** —
  video playback
- **[flutter_html](https://pub.dev/packages/flutter_html)** — rich-text rendering

Reverse-engineering references for DeviantArt's private website endpoints:

- **[gallery-dl](https://github.com/mikf/gallery-dl)** — a downloader that documents how
  DeviantArt's private website data is fetched
- **[deviantart.ts](https://www.npmjs.com/package/deviantart.ts)** — a TypeScript
  DeviantArt API wrapper, used to cross-check endpoint parameters

## Before you start

Ordinary users only need a DeviantArt account — no OAuth app registration is
required. The client bundles a public client id (a Public OAuth client has no
secret, so the client id can be distributed with the app).

> Sign-in requests these OAuth scopes (requested automatically at launch):
> `basic`, `browse`, `collection` (favourites), `user` (watch list),
> `user.manage` (watch/unwatch), `gallery`, `feed`.

### Developers: override the bundled client id

To use your own OAuth app (e.g. for development), override it via
`--dart-define`:

```shell
flutter run -d macos --dart-define=DAKIT_CLIENT_ID=YOUR_PUBLIC_CLIENT_ID
```

> When using your own app, add `dakit://oauth/callback` verbatim to its
> whitelist.

## Run

```shell
flutter pub get
flutter run -d macos     # macOS
flutter run -d android   # Android
flutter run -d windows   # Windows
```

## Proxy

The runtime network path is selected in this order: in-app manual setting,
system proxy, `https_proxy` / `http_proxy` / `all_proxy`, then build setting.
Settings → Proxy accepts `127.0.0.1:<YOUR_PORT>` or
`http://127.0.0.1:<YOUR_PORT>`, persists
the choice, and applies it to API, media, downloads, and hidden public website
adapters. The page tests the App route to DeviantArt. Sign-in happens in the
app's embedded WebView and therefore follows the app network path (a manual
proxy applies to the login page too).

The port is never fixed: use the HTTP/Mixed port shown by your proxy app. On a
phone, `127.0.0.1` is correct only when the proxy runs on that same phone. If it
runs on a computer or router, enter its LAN IP and enable LAN access. The app
tests reachability first, so directly connected users are not pushed toward a
proxy while restricted networks receive the relevant recovery steps.

Apps launched from Finder usually do not inherit terminal variables. On macOS
12/13 an app-only proxy cannot be injected into the hidden browser adapter, so
use the macOS system proxy. See [Networking and proxy](docs/en/networking.md) for
the full priority, platform matrix, and troubleshooting flow.

Environment variables for proxying `flutter pub get` and Gradle builds are in
[Build notes](docs/en/build.md#proxying-builds).

## Build & release

Pushes to `main` trigger CI quality checks and Android/macOS/Windows builds;
pushing a `v*` tag creates a GitHub Release whose notes come from the matching
user-facing `RELEASE_NOTES.md` section.

**One-click release (recommended)**: Actions → **Release** → Run workflow → pick
`patch` / `minor` / `major` (or an exact version) → run. It bumps the version,
commits, pushes the tag, and CI builds and publishes.

Local verification builds:

```shell
flutter build apk --release          # Android APK (requires android/key.properties)
flutter build macos --release        # macOS app
flutter build windows --release      # Windows app
```

Signing, the pinned toolchain (AGP / Gradle / Kotlin / flutter_inappwebview), and
the macOS unsigned-preview contract are detailed in
[Build notes](docs/en/build.md).

## Home & sign-in state

Home is a **native UI** (For you / Daily tabs), plus a first-class **Watched**
bottom tab (DeviantArt's `/watch/deviations` — new artwork from watched artists,
with a recency-sorted avatar strip). “For you” is the website's personalized
`rfy/deviations` feed, fetched with the web Cookie + CSRF session and matching
the site's recommendations. Daily uses the official OAuth API. DeviantArt's
official page inside the app's embedded WebView owns account sign-in,
registration, social providers, and security checks. `dakit://oauth/callback` is
intercepted in the WebView to complete sign-in; there is no second browser
identity to synchronize.

macOS previews use a stable project identity. Sign-in data is stored securely
in a dedicated `DAViewer Account` Keychain (password-safe) item; pending PKCE records are recovery-only and can
never block a live sign-in when they cannot be stored or cleared.

## Login FAQ

- **DAViewer has no account of its own**: you sign in with your DeviantArt account — the app never registers an account or stores a password.
- **Password reset / registration**: tap "Sign in or create an account" and use the actions offered by DeviantArt's official page.
- **Google / Apple / Facebook sign-in**: open DeviantArt's official login page in the app's embedded WebView, then choose a provider right on the page (Google, Apple, and other options are on the page itself). The callback returns to DAViewer after one login.
- **Sign-in and proxies**: sign-in happens in the app's embedded WebView and follows the app network path; a manually entered proxy covers the login page too. If the page cannot open, run the connectivity test before signing in.
- **Check proxy before sign-in**: the native screen shows the effective route and provides both proxy settings and a connectivity test before any web page is opened.
- **Human verification**: this belongs to the official page or identity provider and is completed inside the embedded WebView. DAViewer does not guess that 403/429/503 means an outage or interfere with it.
- **The page did not open or is stuck**: tap the top-right "Done" to close and reopen the login screen. Cancel before starting a completely new transaction.
- **First run and offline recovery**: sign-in is preserved through temporary
  network or provider failures as long as a valid OAuth token exists in secure
  storage. A never-signed-in user is not routed into a failing Home, and an
  established user is never shown as signed-out just because the network is down.
- **Mature content**: DeviantArt account browsing preferences override the app request. Open Settings → DeviantArt account settings → Mature content settings.
- **Settings while sign-in is broken**: the gear on the login screen keeps language, proxy, diagnostics, updates, and About reachable without authentication.
- **macOS security prompt at first sign-in**: macOS keeps a built-in “password
  safe” (officially called the Keychain). Before storing your sign-in state
  there, the system asks for your permission — just like any well-behaved app
  saving your password. When you see “DAViewer Account wants to use confidential
  information”, choose **Allow** or **Always Allow**: this simply saves your
  sign-in securely on this Mac — nothing is uploaded and no other passwords are
  read. If macOS asks for your Mac password because the safe is locked, that’s
  just macOS unlocking your own keychain; the app never collects or uploads
  your password.

See [Authentication and session recovery](docs/en/authentication.md) for the full
state contract.

## Contributing

All contributions are welcome — issues, bug fixes, features, and docs. See
[CONTRIBUTING.md](CONTRIBUTING.md). Report security issues via
[SECURITY.md](SECURITY.md), and see [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) for
community guidelines.

1. Fork the repository and branch from `main`;
2. Run `dart format lib test`, `flutter analyze`, and `flutter test`;
3. Open a PR describing what changed and why.

The SDK the client depends on is [DAKit](https://github.com/redtidev1918/DAKit)
(published to pub.dev); SDK changes belong there, and the two are released
together.

If this project is useful to you, **star it** so more people can find it.

## Notes

- `DAViewer` is a third-party client and is not affiliated with DeviantArt;
- The client does not store a `client_secret`;
- All account authorization uses DeviantArt's official page inside the app's
  embedded WebView. DAViewer never implements or reads an account/password form
  of its own.

# DAViewer

<p align="center">
  <img src="assets/icon/icon.png" alt="DAViewer" width="128" />
</p>

**Language / 语言:** [中文](README.md) · English

DAViewer is an open-source, third-party DeviantArt client written in Flutter for Android, Windows, and macOS. Browsing, search, favourites, watch, and downloads all live in one app.

DAViewer is not an official DeviantArt app and has no affiliation or partnership with DeviantArt.

[![GitHub license](https://img.shields.io/github/license/redtidev1918/DAViewer?style=flat)](LICENSE) [![GitHub release](https://img.shields.io/github/v/release/redtidev1918/DAViewer?style=flat)](https://github.com/redtidev1918/DAViewer/releases) [![Platforms](https://img.shields.io/badge/platform-Android%20%7C%20Windows%20%7C%20macOS-blue?style=flat)](#download-and-install) [![Docs](https://img.shields.io/badge/Docs-documentation-6366f1?style=flat-square)](https://redtidev1918.github.io/DAViewer/#/en/)

**[Download the latest release](https://github.com/redtidev1918/DAViewer/releases)** · [Documentation](https://redtidev1918.github.io/DAViewer/#/en/) · [Getting started](#getting-started) · [FAQ](#faq)

## Screenshots

<table align="center">
  <tr>
    <td align="center"><img src="docs/screenshots/home_feed.jpg" width="200" /><br /><sub>Home feed</sub></td>
    <td align="center"><img src="docs/screenshots/artwork_detail.jpg" width="200" /><br /><sub>Artwork detail</sub></td>
    <td align="center"><img src="docs/screenshots/related_works.jpg" width="200" /><br /><sub>Related works and original download</sub></td>
  </tr>
</table>

## What you can do

### Browse and discover

- **For you**: a personalized feed built from your DeviantArt web session. When that session is missing or has expired, the app asks you to sign in again instead of passing off generic content as recommendations.
- **Daily**: DeviantArt's daily picks, fetched through the official API.
- **Watched**: a separate tab in the bottom bar that gathers new work from the artists you watch, with a strip for switching between them.
- **Search**: results as you type (about 450 ms debounce), switchable between artworks and users. Typing `#tag` jumps straight to that tag, and artwork results can be sorted by default or newest.
- **Tags**: browse a tag, sorted by recent or popular.
- **Open a link**: the link button in the Home app bar accepts a DeviantArt artwork or artist URL and jumps to it.

Search, tags, and the watched feed all require signing in.

### Artwork and artists

- **Artwork detail**: large-image viewing and paged multi-image works, with double-tap zoom. Swipe left or right to move to the adjacent artwork, which is prefetched.
- **Video and animated works**: video plays automatically and loops, with a scrubber, volume, and playback speed; failed loads can be retried. GIF works carry a badge.
- **Work information**: title, author, description, tags, and whether the original is available plus its file size; one tap to share.
- **Artist pages**: profile, gallery, saved works, journals, and custom folders, with in-gallery search.
- **More like this**: keep discovering related works from an artwork, refreshable at any time.
- **Watch**: follow or unfollow an artist from their page, and review the artists you watch in the watched list.

### Favourites and interaction

- **Favourites**: favourite or unfavourite from the artwork page, and browse them under the Favourites tab in the bottom bar.
- **Collections**: open your collections and the works inside them.
- **Notifications**: DeviantArt's message feed, with the unread count on the Home bell. Read state is stored locally, because DeviantArt has no public mark-as-read endpoint.
- **Visit history**: the artworks you opened recently, kept on this device, up to 200 entries. Reach it from the history button in the search screen and clear it in one tap.

### Downloads and personalization

- **Original first**: when a work can be downloaded, its original is saved directly and its file size is shown. Multi-image works can be downloaded all at once.
- **Fallback when restricted**: if the original is paid, restricted, or gone, only image-only works fall back to the image currently on screen (which is not the original). Works that contain video never fall back, and a video poster is never saved as if it were a video file. Paid, private, and copyright-restricted works cannot be downloaded.
- **Download management**: the Downloads tab in the bottom bar shows progress, and transfers can be paused, resumed, cancelled, and retried. Finished files can be opened; on desktop you can also open the containing folder, and on Android the file is saved to the system Downloads folder. Completed records can be cleared in one tap.
- **Settings**: light / dark / system, Chinese or English, clear cache, check for updates, view or import/export your DeviantArt account cookies, and sign in or out.
- **Diagnostics**: generates a pre-filled GitHub issue link. The log is stripped of access tokens, cookies, and similar sensitive values first, and you review it before submitting.

## Download and install

Stable builds live on the [Releases](https://github.com/redtidev1918/DAViewer/releases) page. Pick the file for your platform:

| Platform | File | Install |
| --- | --- | --- |
| Android | `DAViewer-v<version>.apk` | Open the APK to install |
| Windows | `DAViewer-v<version>-windows.zip` | Extract, then run `daviewer.exe` |
| macOS | `DAViewer-v<version>-macos-unsigned-preview.zip` | Extract, then open `DAViewer.app` |

- **Android**: requires Android 7.0 or later. Your device will warn about installing an app from an unknown source; allow it when prompted.
- **Windows**: keep every file in the extracted folder together. Moving `daviewer.exe` out on its own will stop the app from starting.
- **macOS**: requires macOS 12 or later. The current build is an unsigned, unnotarized preview: on first launch, right-click the app in Finder and choose **Open**, or allow it under System Settings → Privacy & Security. The app stores your sign-in tokens in the system keychain, so choose **Allow** if the system asks.

The release page also publishes `SHA256SUMS` if you want to verify your download. If a version is marked as a Pre-release it is a preview build; most people should take the one marked Latest. The current version number and file sizes are listed on the [download page](docs/en/download.md).

## Getting started

1. Download and open the app.
2. On first launch it opens the sign-in screen directly. Choose **Sign in or create an account** and finish signing in on DeviantArt's official page inside the app.
3. Once you are back on the Home feed, you can browse, search, favourite, and download.

Which sign-in method you use is up to DeviantArt's own page; DAViewer only embeds it and never sees your password.

A single sign-in establishes two separate sessions, which serve different purposes and expire independently:

- **The OAuth session** drives DeviantArt's official API: Daily, artwork information, favourites, watch, downloads, and the user results in search. Its tokens are kept in the system keychain or credential store.
- **The web session (cookies)** drives features DeviantArt only exposes on its website: the personalized feed, in-gallery search, and the artwork results in search (with the official API as a fallback). It is kept in the app's data directory.

So a successful sign-in does not mean everything is available: when the web session expires, the personalized feed and gallery search ask you to sign in again while the rest of the app keeps working. A healthy web session is not a substitute for OAuth either.

Very little is reachable while signed out. Only the sign-in screen, Settings, and visit history work; search, tags, favourites, downloads, notifications, artist pages, and artwork detail all require signing in.

Signing out (Settings → Sign out) removes the OAuth tokens, the browser cookies, and the local web-session file.

The full state rules are in [Authentication and session recovery](docs/en/authentication.md).

## FAQ

**I already signed in, so why is it asking me to sign in again?**

The personalized feed and gallery search use the web session, which is separate from the OAuth session and expires on its own. Sign in again inside the app when prompted. If the cause is a blocked network or an unavailable proxy, the app says so rather than reporting "not signed in"; in that case switching network or proxy node and refreshing after a minute or two works better than signing in repeatedly.

**The personalized feed or Daily will not load. What now?**

Check that your network and proxy work (Settings → Proxy has a connectivity test), then pull to refresh. The personalized feed also refreshes on its own when the app returns to the foreground after more than 10 minutes.

**How do I see mature content?**

DAViewer can only request mature content; whether it is shown is decided by the browsing preference on your DeviantArt account. Open DeviantArt's own mature-content setting from Settings → DeviantArt account settings, then sign in again in the app so the web session picks it up. Some age-restricted multi-image works are not served by the official API and need a valid web session.

**Why can't I download some originals?**

Paid, private, subscriber-only, or copyright-restricted works do not offer their original, and the app shows the reason. When the original is unavailable, only image-only works fall back to the image on screen — that is not the original. Works containing video do not fall back, and a video poster is never treated as a video download.

**How do I configure a proxy?**

Settings → Proxy lets you enter an address by hand as `host:port` or `http://host:port`; use the HTTP / Mixed port your proxy app shows. With nothing set, the app tries the system proxy, then environment variables (`https_proxy` / `http_proxy` / `all_proxy`), then a build-time proxy, and finally a direct connection.

Only HTTP CONNECT proxies are supported — not SOCKS5, not proxy URLs with credentials, and not PAC. Support in the sign-in WebView also differs by platform: it applies process-wide on Android, through WebView2 arguments on Windows, and on macOS 14 or later; macOS 12 and 13 can only rely on the system proxy. See [Networking and proxy](docs/en/networking.md) for details.

**macOS says the developer cannot be verified.**

The current build is an unsigned, unnotarized preview. Right-click the app in Finder and choose **Open**, or allow it under System Settings → Privacy & Security.

**Does "check for updates" download a new version automatically?**

No. The app quietly checks GitHub for the latest version from time to time and shows a notice when one exists. Tapping the notice only opens the Releases page in your browser; the app never downloads or installs an update by itself.

**How do I report a problem?**

Settings → Diagnostics generates a pre-filled GitHub issue link. The log has tokens, cookies, and similar values removed first, and you can review it before submitting. You can also open an issue directly on [GitHub](https://github.com/redtidev1918/DAViewer/issues). For security reports, see [SECURITY.md](SECURITY.md).

## About DeviantArt

- DAViewer is a community-built third-party client. It is not affiliated with DeviantArt and has no authorization or partnership from DeviantArt. DeviantArt is a trademark of its owner.
- Sign-in uses DeviantArt's official page. The client does not store a `client_secret` and never sees your password.
- Artwork belongs to the artists who made it. The download feature only saves publicly accessible files you already have access to; please respect DeviantArt's terms of service and each work's usage terms.
- The app depends on DeviantArt's official API and some website endpoints. Those can change at any time, so related features may stop working.

## Advanced and development

### Run locally

```shell
flutter pub get
flutter devices          # List device IDs
flutter run -d macos
flutter run -d windows
flutter run -d <device-id>  # Android
```

Requires Flutter 3.47.1 (the version CI pins) and Dart 3.13.1 or later. The app depends on published DAKit packages; versions are in [pubspec.yaml](pubspec.yaml).

### How the app is structured

DAViewer is a Flutter app, and the reusable parts live in the SDK [DAKit](https://github.com/redtidev1918/DAKit) by the same author: DAKit covers OAuth, the official API, the website compatibility adapters, and background transfers, while DAViewer owns the UI, routing, and platform integration. See [Architecture](docs/en/architecture.md) for the boundary and the trade-offs behind it.

### Build

```shell
flutter build apk --release          # Android, needs android/key.properties
flutter build macos --release        # macOS
flutter build windows --release      # Windows
```

Release builds need `--dart-define=DAVIEWER_VERSION=<version>`, otherwise the app cannot report updates correctly. See [Build notes](docs/en/build.md) for the toolchain, signing, and the unnotarized macOS preview.

### Release

ReleaseGraph and release-please drive releases through [.release-policy.yml](.release-policy.yml). The Chinese release notes for each version live in `.github/release-notes/<version>.md`, and the **Release** workflow under Actions can validate or repair an existing version. Manual pre-release verification is recorded in the [release gate](docs/release-gate.md) and the [regression catalog](docs/regressions/README.md).

### Use your own OAuth app

You do not need one for normal use. To use your own public client, pass `--dart-define=DAKIT_CLIENT_ID=YOUR_PUBLIC_CLIENT_ID` and add `dakit://oauth/callback` to its whitelist.

### Before you commit

For Dart changes, run:

```shell
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

## Documentation

This README covers the overview and getting started; sign-in states, proxy details, the architectural boundary, and build and release flows live on the [documentation site](https://redtidev1918.github.io/DAViewer/#/en/) and under `docs/`. Pick a document by task:

| What you want | Where |
| --- | --- |
| Download a build | [Download page](docs/en/download.md) |
| Solve sign-in, session, and common issues | [Authentication](docs/en/authentication.md) |
| Configure networking and proxies | [Networking](docs/en/networking.md) |
| Understand the app/SDK boundary | [Architecture](docs/en/architecture.md) |
| Build and release locally | [Build notes](docs/en/build.md) |
| Check pre-release evidence and remaining risks | [Release gate](docs/release-gate.md), [Regression catalog](docs/regressions/README.md) (the gate document is in Chinese) |

Issues, pull requests, and documentation improvements are all welcome — see [CONTRIBUTING.md](CONTRIBUTING.md). Security reports go to [SECURITY.md](SECURITY.md).

## Acknowledgements

DAViewer builds on [DAKit](https://github.com/redtidev1918/DAKit) and [Flutter](https://flutter.dev); the embedded
WebView, state management, routing, image cache, video playback, and rich text come from
`flutter_inappwebview`, `flutter_riverpod`, `go_router`, `cached_network_image`,
`chewie` / `video_player`, and `flutter_html` respectively. See [pubspec.yaml](pubspec.yaml) for the full list.
Private website endpoint research referenced [gallery-dl](https://github.com/mikf/gallery-dl) and
[deviantart.ts](https://www.npmjs.com/package/deviantart.ts).

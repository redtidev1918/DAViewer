# DAViewer

<p align="center">
  <img src="assets/icon/icon.png" alt="DAViewer" width="128" />
</p>

DAViewer is an open-source, third-party DeviantArt client for Android, Windows, and macOS. Browse artwork, discover artists, favourite what you like, and download the images you are allowed to save.

DAViewer is not an official DeviantArt app and has no affiliation or partnership with DeviantArt.

**[Download the latest release](https://github.com/redtidev1918/DAViewer/releases)** · [Documentation](https://redtidev1918.github.io/DAViewer/#/en/) · [Getting started](#getting-started) · [FAQ](#faq)

[![GitHub release](https://img.shields.io/github/v/release/redtidev1918/DAViewer?style=flat)](https://github.com/redtidev1918/DAViewer/releases) [![GitHub license](https://img.shields.io/github/license/redtidev1918/DAViewer?style=flat)](LICENSE)

**Language / 语言:** [中文](README.md) · English

## Screenshots

<p align="center">
  <img src="docs/screenshots/home_feed.jpg" width="30%" alt="Home feed" />
  <img src="docs/screenshots/artwork_detail.jpg" width="30%" alt="Artwork detail" />
  <img src="docs/screenshots/related_works.jpg" width="30%" alt="Related works and original download" />
</p>

<p align="center"><sub>Home feed · Artwork detail · Related works and original download</sub></p>

## What you can do

### Browse and discover

- **For you**: a personalized feed built from your DeviantArt web session.
- **Daily**: DeviantArt's daily picks.
- **Watched**: new work from the artists you watch, in one feed, with a strip for switching between artists.
- **Search and tags**: results as you type, switchable between artwork and users; type `#tag` to jump straight to a tag, and sort artwork results by default or newest.
- **Open a link**: paste a DeviantArt artwork or artist URL into the link button in the Home app bar.

### Artwork

- **Large images and multi-image works**: full-screen viewing, double-tap zoom, and paged works, with swiping between adjacent artworks.
- **Video and animated works**: video plays automatically and loops, with a scrubber, volume, and playback speed.
- **Work information**: title, author, description, tags, and whether the original can be downloaded plus its file size.
- **More like this**: keep discovering related works from an artwork, and refresh at any time.

### Artists and interaction

- **Artist pages**: profile, gallery, saved works, journals, and custom folders, with search inside a gallery.
- **Watch**: follow or unfollow from an artist's page, and review the artists you watch in the watched list.
- **Favourites**: favourite from an artwork page, and browse your favourites and collections under the Favourites tab.
- **Notifications**: DeviantArt's message feed, with the unread count on the Home bell.

### Downloads

- **Original first**: when a work can be downloaded, its original is saved directly, and multi-image works can be downloaded all at once.
- **Fallback when restricted**: if the original is paid, restricted, or gone, only image-only works fall back to the image currently on screen (which is not the original); works that contain video never fall back.
- **Download management**: watch progress under the Downloads tab, pause, resume, cancel, and retry a transfer, and open a finished file.

### Personalization and tools

- **Theme and language**: light / dark / system, with a Chinese or English interface.
- **Proxy**: enter a proxy address by hand, or let the app use the system proxy.
- **Visit history**: the artworks you opened recently, kept on this device, up to 200 entries, clearable in one tap.
- **Update check**: tells you when a new version exists and opens the release page in your browser.

Browsing, search, favourites, watch, and downloads all require signing in with a DeviantArt account; while signed out, only the sign-in screen, Settings, and visit history are usable.

## Download and install

Builds are on the [Releases](https://github.com/redtidev1918/DAViewer/releases) page — pick the file for your platform:

- **Android**: download `DAViewer-v<version>.apk` and open it to install. Requires Android 7.0 or later; allow installing from an unknown source when your device asks.
- **Windows**: download `DAViewer-v<version>-windows.zip`, extract it, and run `daviewer.exe`. Keep the extracted folder together — moving `daviewer.exe` out on its own will stop the app from starting.
- **macOS**: download `DAViewer-v<version>-macos-unsigned-preview.zip`, extract it, and open `DAViewer.app`. Requires macOS 12 or later; this is an unsigned, unnotarized preview, so the first launch needs a right-click and **Open**.

Take the build marked Latest; one marked Pre-release is a preview. The release page also publishes `SHA256SUMS` if you want to verify your download, and the current version and file sizes are on the [download page](docs/en/download.md).

## Getting started

1. Download and open the app; the first launch goes straight to the sign-in screen.
2. Choose **Sign in or create an account** and finish signing in on DeviantArt's official page inside the app. How you sign in is up to DeviantArt — DAViewer never sees your password.
3. You are back on the Home feed, ready to browse, search, favourite, and download.

Some features, such as the personalized feed, use DeviantArt's web session, which is stored separately from your sign-in and can expire on its own. If the app still asks you to sign in, or the feed will not load, sign in once more in the app as prompted, or check your network and proxy.

See [Authentication and session recovery](docs/en/authentication.md) for the full state rules.

## FAQ

**I signed in, so why is it asking me to sign in again?**

The personalized feed and a few related features use DeviantArt's web session, which is stored separately from your sign-in and expires on its own. Sign in once more inside the app when prompted. If a network challenge is the cause, the app says so instead of reporting "not signed in" — switching network or proxy node and refreshing after a minute or two works better than signing in repeatedly. See [Authentication and session recovery](docs/en/authentication.md).

**The personalized feed or Daily will not load. What now?**

Check that your network and proxy work (Settings → Proxy has a connectivity test), then pull to refresh.

**How do I see mature content?**

DAViewer can only request mature content; whether it is shown is decided by the browsing preference on your DeviantArt account. Open DeviantArt's own setting from Settings → DeviantArt account settings, then sign in again in the app.

**Why can't I download some originals?**

Paid, private, subscriber-only, or copyright-restricted works do not offer their original, and the app shows the reason on the artwork page; see [Downloads](#downloads) for the fallback rules.

**How do I configure a proxy?**

Enter an address under Settings → Proxy as `host:port` or `http://host:port`, using the HTTP / Mixed port your proxy app shows; with nothing set, the app falls back to the system proxy and environment variables. Only HTTP CONNECT proxies are supported — not SOCKS5, not proxy URLs with credentials, and not PAC — and WebView coverage differs by platform. See [Networking and proxy](docs/en/networking.md).

**macOS says the developer cannot be verified.**

This is an unsigned, unnotarized preview. Right-click the app in Finder and choose **Open**, or allow it under System Settings → Privacy & Security.

**How do I report a problem?**

Settings → Diagnostics generates a pre-filled GitHub issue link; the log has tokens, cookies, and similar values removed first, and you can review it before submitting. You can also open an issue directly on [GitHub](https://github.com/redtidev1918/DAViewer/issues). For security reports, see [SECURITY.md](SECURITY.md).

## Development and contributing

DAViewer is a Flutter app, and the reusable parts live in the SDK [DAKit](https://github.com/redtidev1918/DAKit) by the same author: DAKit covers OAuth, the official API, the website compatibility adapters, and background transfers, while DAViewer owns the UI, routing, and platform integration. See [Architecture](docs/en/architecture.md) for the boundary and its trade-offs.

```shell
flutter pub get
flutter run -d macos        # or windows / an Android device ID
```

Requires Flutter 3.47.1 (the version CI pins). [Build notes](docs/en/build.md) and [CONTRIBUTING.md](CONTRIBUTING.md) cover building, releasing, and the checks to run before committing.

<details>
<summary>Build commands and pre-commit checks</summary>

```shell
flutter build apk --release     # Android, needs android/key.properties
flutter build macos --release
flutter build windows --release
```

Release builds need `--dart-define=DAVIEWER_VERSION=<version>`, otherwise the app cannot report updates correctly. To use your own OAuth public client, add `--dart-define=DAKIT_CLIENT_ID=<YOUR_PUBLIC_CLIENT_ID>` and put `dakit://oauth/callback` on its whitelist; normal use does not need one.

For Dart changes, run:

```shell
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

</details>

## Documentation

This README covers the overview and getting started; sign-in states, proxy details, the architectural boundary, and build and release flows live on the [documentation site](https://redtidev1918.github.io/DAViewer/#/en/) and under `docs/`. Pick a document by task:

| What you want | Where |
| --- | --- |
| Download a build | [Download page](docs/en/download.md) |
| Solve sign-in, session, and common issues | [Authentication](docs/en/authentication.md) |
| Configure networking and proxies | [Networking](docs/en/networking.md) |
| Understand the app/SDK boundary | [Architecture](docs/en/architecture.md) |
| Build and release locally | [Build notes](docs/en/build.md) |
| Pre-release evidence and risks | [Release gate](docs/release-gate.md), [regressions](docs/regressions/README.md) (zh) |

Issues, pull requests, and documentation improvements are all welcome. Security reports go to [SECURITY.md](SECURITY.md).

## About this project

- DAViewer is a community-built third-party client. It is not affiliated with DeviantArt and has no authorization or partnership from DeviantArt. DeviantArt is a trademark of its owner.
- Sign-in uses DeviantArt's official page. The client does not store a `client_secret` and never sees your password.
- Artwork belongs to the artists who made it. The download feature only saves publicly accessible files you already have access to; please respect DeviantArt's terms of service and each work's usage terms.
- The app depends on DeviantArt's official API and some website endpoints. Those can change at any time, so related features may stop working.
- The project is under the [MIT licence](LICENSE).

## Acknowledgements

DAViewer builds on [DAKit](https://github.com/redtidev1918/DAKit) and [Flutter](https://flutter.dev); the embedded
WebView, state management, routing, image cache, video playback, and rich text come from
`flutter_inappwebview`, `flutter_riverpod`, `go_router`, `cached_network_image`,
`chewie` / `video_player`, and `flutter_html` respectively. See [pubspec.yaml](pubspec.yaml) for the full list.
Private website endpoint research referenced [gallery-dl](https://github.com/mikf/gallery-dl) and
[deviantart.ts](https://www.npmjs.com/package/deviantart.ts).

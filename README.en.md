# DAViewer

<p align="center">
  <img src="assets/icon/icon.png" alt="DAViewer" width="160" />
</p>

**Language:** English · [中文](README.md)

DeviantArt has discontinued its official client app. DAViewer is an open-source client built on [DAKit](https://github.com/redtidev1918/DAKit) that provides the website's main features as a native app for Android, macOS, and Windows — ready to use, with no OAuth app of your own to register.

[![GitHub license](https://img.shields.io/github/license/redtidev1918/DAViewer?style=flat)](LICENSE) [![GitHub release](https://img.shields.io/github/v/release/redtidev1918/DAViewer?style=flat)](https://github.com/redtidev1918/DAViewer/releases) [![Platforms](https://img.shields.io/badge/platform-Android%20%7C%20macOS%20%7C%20Windows-blue?style=flat)](https://github.com/redtidev1918/DAViewer/releases) [![Docs](https://img.shields.io/badge/Docs-documentation-6366f1?style=flat-square)](https://redtidev1918.github.io/DAViewer/)

## Install

Download the package for your platform from [Releases](https://github.com/redtidev1918/DAViewer/releases):

- **Android**: `DAViewer-v<version>.apk`
- **Windows**: `DAViewer-v<version>-windows.zip` — unzip and run `DAViewer.exe`; no service, no system settings, no administrator rights
- **macOS 12+**: `DAViewer-v<version>-macos-unsigned-preview.zip` — universal Intel and Apple Silicon build; unzip and drag to Applications

macOS blocks the first launch, because this is a free community preview without an Apple signature. Right-click the app icon in Finder and choose **Open** — it runs normally after that, and the app never uploads or collects any data.

## Screenshots

<table align="center">
  <tr>
    <td align="center"><img src="docs/screenshots/home_feed.jpg" width="200" /><br /><sub>Home feed</sub></td>
    <td align="center"><img src="docs/screenshots/artwork_detail.jpg" width="200" /><br /><sub>Artwork detail</sub></td>
    <td align="center"><img src="docs/screenshots/related_works.jpg" width="200" /><br /><sub>Related works</sub></td>
  </tr>
</table>

## Features

- **Sign in**: the app opens DeviantArt's official login page in an embedded WebView — pick DeviantArt, Google, Apple, or Facebook there. One login sets up both the official OAuth session and the web session
- **Home**: a native UI with "For you" (the website's personalized feed) and "Daily" (official API) tabs, plus a "Watched" bottom tab
- **Search**: results as you type with history; paste a DeviantArt link to jump straight to an artwork or artist; "Recommended for you" and popular tags show previews
- **Artwork detail**: swipe between works with adjacent images prefetched; pinch zoom, paged multi-image works, relative publish and update times
- **Visit history**: locally remembers the works you opened, up to 200, reachable from the search screen, clearable in one tap, never uploaded
- **Media**: shared image zoom; highest-quality video that autoplays, loops, seeks, and retries; GIF badges and cached rich-text images
- **Related content**: more like this, similar artists, collections, and more from the artist on the detail page
- **Artist**: profile, gallery (searchable), custom folders, favourites, watch
- **Social**: favourite (with state), watch/unwatch, watched-user list, notifications (unread dot + local mark-as-read)
- **Download**: real-time original-file permission check; when restricted, it explains why and saves the highest-quality preview instead; long-press to download one image, with a completion toast and open file/folder
- **Sharing**: native share sheet for artwork, artists, gallery folders, collections, and tags
- **Settings**: light / dark / system, Chinese / English, clear cache, check for updates — new versions show a dismissible banner, never a modal or an auto-download
- **Problem reporting**: diagnostics generate a pre-filled GitHub issue; the app collects and uploads nothing

## Relationship with DAKit

DAViewer is the app; DAKit is the SDK. OAuth, official API mapping, domain models, and background transfers live in DAKit; generic private-website protocol parsing lives in the optional `dakit_web` package; WebView sessions and native interaction live in DAViewer. The client only depends on published packages and never copies SDK code — see [pubspec.yaml](pubspec.yaml) for versions and [Architecture](docs/en/architecture.md) for the full boundary.

## Run

```shell
flutter pub get
flutter run -d macos     # macOS
flutter run -d android   # Android
flutter run -d windows   # Windows
```

Ordinary users only need a DeviantArt account — no OAuth app registration: the bundled client id is public and has no secret. To use your own OAuth app while developing, pass `--dart-define=DAKIT_CLIENT_ID=YOUR_PUBLIC_CLIENT_ID` and add `dakit://oauth/callback` to its whitelist verbatim.

## Proxy

The app picks its network path in this order: in-app manual setting → system proxy → `https_proxy` / `http_proxy` / `all_proxy` → build setting. The choice is persisted and applies to the API, images, downloads, and the hidden website adapters. Use the HTTP/Mixed port your proxy app shows — there is no fixed value; on a phone `127.0.0.1` is only right when the proxy runs on that same phone. The app tests direct connectivity first, so users who can connect directly are not pushed toward a proxy. See [Networking and proxy](docs/en/networking.md) for the full rules.

## Build & release

Pushing to `main` runs CI quality checks; pushing a `v*` tag creates a GitHub Release whose notes come from `RELEASE_NOTES.md`. To release, use Actions → **Release** → Run workflow and pick `patch` / `minor` / `major`, or an exact version. Local builds:

```shell
flutter build apk --release          # Android APK (requires android/key.properties)
flutter build macos --release        # macOS app
flutter build windows --release      # Windows app
```

Signing, the pinned toolchain, and the macOS unsigned-preview contract are detailed in [Build notes](docs/en/build.md).

## Login FAQ

- **Accounts**: you sign in with your DeviantArt account; the app never registers an account or stores a password. Password resets and registration happen on DeviantArt's official page.
- **Google / Apple / Facebook sign-in**: choose a provider on DeviantArt's official login page inside the app's embedded WebView; the callback returns to DAViewer after one login.
- **Human verification**: this belongs to the official page or identity provider and is completed inside the embedded WebView. The app does not interfere.
- **The page did not open or is stuck**: tap "Done" at the top right and reopen it. You can also run the connectivity test before signing in.
- **Mature content**: Settings → DeviantArt account settings → Mature content settings. Your account's browsing preferences win.
- **First run and offline**: with a valid token in secure storage, sign-in survives a temporary outage; if the login page will not open, the gear at the top right still reaches language, proxy, diagnostics, and update checks.
- **macOS security prompt at first sign-in**: macOS asks permission before storing your sign-in in the built-in keychain, exactly as well-behaved apps do when saving a password — choose **Allow** or **Always Allow**. Nothing is uploaded; if macOS asks for your Mac password, that is macOS unlocking your own keychain.

See [Authentication and session recovery](docs/en/authentication.md) for the full state contract.

## Contributing

Issues, bug fixes, features, and docs are all welcome — see [CONTRIBUTING.md](CONTRIBUTING.md). Report security issues via [SECURITY.md](SECURITY.md); community guidelines are in [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).

1. Fork the repository and branch from `main`;
2. Run `dart format lib test`, `flutter analyze`, and `flutter test`;
3. Open a PR describing what changed and why.

SDK changes belong in [DAKit](https://github.com/redtidev1918/DAKit); the two are released together. If this project is useful to you, **star it** so more people can find it.

## Notes

- DAViewer is a third-party client and is not affiliated with DeviantArt;
- The client does not store a `client_secret`;
- All account authorization uses DeviantArt's official page inside the app's embedded WebView; DAViewer never implements or reads an account/password form of its own;
- Private website endpoint research referenced [gallery-dl](https://github.com/mikf/gallery-dl) and [deviantart.ts](https://www.npmjs.com/package/deviantart.ts).

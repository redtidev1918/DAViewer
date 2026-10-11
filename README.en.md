# DAViewer

<p align="center">
  <img src="assets/icon/icon.png" alt="DAViewer" width="160" />
</p>

**Language / 语言:** [中文](README.md) · English

DAViewer is an open-source, third-party DeviantArt client built on [DAKit](https://github.com/redtidev1918/DAKit) for Android, macOS, and Windows. Browse artwork and artist galleries, save favourites, watch artists, and download images.

[Full documentation](https://redtidev1918.github.io/DAViewer/#/en/)

[![GitHub license](https://img.shields.io/github/license/redtidev1918/DAViewer?style=flat)](LICENSE) [![GitHub release](https://img.shields.io/github/v/release/redtidev1918/DAViewer?style=flat)](https://github.com/redtidev1918/DAViewer/releases) [![Platforms](https://img.shields.io/badge/platform-Android%20%7C%20macOS%20%7C%20Windows-blue?style=flat)](https://github.com/redtidev1918/DAViewer/releases) [![Docs](https://img.shields.io/badge/Docs-documentation-6366f1?style=flat-square)](https://redtidev1918.github.io/DAViewer/)

## Download

Grab your platform's file from [Releases](https://github.com/redtidev1918/DAViewer/releases):

- **Android**: `DAViewer-v<version>.apk`
- **Windows**: `DAViewer-v<version>-windows.zip`
- **macOS**: `DAViewer-v<version>-macos-unsigned-preview.zip`

On Android, install the APK. On Windows, extract the ZIP and run `daviewer.exe`, keeping the other files alongside it. On macOS, extract the ZIP and open `DAViewer.app`. The macOS package is an unnotarized preview; on first launch, right-click the app in Finder and choose **Open**.

Choose **Sign in or create an account** and complete sign-in on DeviantArt's official page in the embedded WebView. For you requires a web session; Daily uses the OAuth API. See [Authentication](docs/en/authentication.md) for session recovery.

## Screenshots

<table align="center">
  <tr>
    <td align="center"><img src="docs/screenshots/home_feed.jpg" width="200" /><br /><sub>Home feed</sub></td>
    <td align="center"><img src="docs/screenshots/artwork_detail.jpg" width="200" /><br /><sub>Artwork detail</sub></td>
    <td align="center"><img src="docs/screenshots/related_works.jpg" width="200" /><br /><sub>Related works</sub></td>
  </tr>
</table>

## Features

- **Sign in**: DeviantArt's official login page in an embedded WebView, with DeviantArt / Google / Apple / Facebook
- **Home**: For you (personalized feed), Daily, and Watched
- **Search**: results as you type + history; paste a link to jump to an artwork or artist
- **Artwork detail**: swipe between works with adjacent images prefetched; pinch zoom, paged multi-image works
- **Visit history**: locally keeps the works you opened, up to 200, reachable from the search screen and clearable there
- **Media**: video at highest quality with autoplay, looping, seeking, and retry; GIF badges
- **Related content**: more like this, similar artists, collections, more from the artist
- **Artist**: profile, searchable gallery, custom folders, favourites, watch
- **Social**: favourite (with state), watch/unwatch, watched-user list, notifications
- **Download**: saves the highest-quality preview when the original is restricted; long-press one image to download it, then open the file or folder
- **Sharing**: native share sheet for artwork, artists, gallery folders, collections, tags
- **Settings**: light / dark / system, Chinese / English, clear cache, check for updates
- **Diagnostics**: one tap to generate a pre-filled GitHub issue

## Development

```shell
flutter pub get
flutter devices         # List available device IDs
flutter run -d macos     # macOS
flutter run -d <device-id> # Android: use an ID from flutter devices
flutter run -d windows   # Windows
```

The app depends on published DAKit packages. Versions are in [pubspec.yaml](pubspec.yaml); the app/SDK boundary is in [Architecture](docs/en/architecture.md).

Ordinary users need no OAuth app. To use your own, pass `--dart-define=DAKIT_CLIENT_ID=YOUR_PUBLIC_CLIENT_ID` and add `dakit://oauth/callback` to its whitelist.

## Proxy

Proxy selection follows this order: Settings → Proxy, system proxy, `https_proxy` / `http_proxy` / `all_proxy`, build-time `DAKIT_PROXY_URL`, then a direct connection. Use the HTTP/Mixed port shown by your proxy app. See [Networking and proxy](docs/en/networking.md) for each platform's sign-in WebView support.

## Release

ReleaseGraph and release-please manage releases through [.release-policy.yml](.release-policy.yml). Chinese release notes live in `.github/release-notes/<version>.md`. Actions → **Release** can validate or repair an existing version. See [Build notes](docs/en/build.md) for the workflow and inputs.

```shell
flutter build apk --release          # Android APK, needs android/key.properties
flutter build macos --release        # macOS
flutter build windows --release      # Windows
```

Signing and the pinned toolchain are in [Build notes](docs/en/build.md).

## Login issues

- **The page did not open or is stuck**: tap "Done" at the top right and reopen it; you can run the connectivity test first.
- **Mature content**: Settings → DeviantArt account settings → Mature content settings.
- **Keychain prompt on macOS**: choose Allow when the system requests access to the app's account storage.

State and recovery rules are in [Authentication and session recovery](docs/en/authentication.md).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for bug reports, PRs, and documentation changes. For Dart changes, run `dart format lib test`, `flutter analyze`, and `flutter test`. Security reports go to [SECURITY.md](SECURITY.md).

## Documentation

Choose a document by task, or browse the [docs site](https://redtidev1918.github.io/DAViewer/#/en/):

| What you want | Where |
| --- | --- |
| Download a build | [Download page](docs/en/download.md) |
| Sign-in and common issues | [Authentication](docs/en/authentication.md) |
| Networking and proxies | [Networking](docs/en/networking.md) |
| App/SDK boundary | [Architecture](docs/en/architecture.md) |
| Local builds and releases | [Build notes](docs/en/build.md) |
| Check release evidence and remaining risks | [Release gate](docs/release-gate.md), [Regression catalog](docs/regressions/README.md) (gate in Chinese) |

## Acknowledgements

DAViewer builds on [DAKit](https://github.com/redtidev1918/DAKit) and [Flutter](https://flutter.dev); the embedded
WebView, state management, routing, image cache, video playback, and rich text come from
`flutter_inappwebview`, `flutter_riverpod`, `go_router`, `cached_network_image`,
`chewie` / `video_player`, and `flutter_html` respectively. See [pubspec.yaml](pubspec.yaml) for the full list.
Private website endpoint research referenced [gallery-dl](https://github.com/mikf/gallery-dl) and
[deviantart.ts](https://www.npmjs.com/package/deviantart.ts).

## Notes

- DAViewer is a third-party client and is not affiliated with DeviantArt.
- Sign-in uses DeviantArt's official page; the client does not store a `client_secret`.

# DAViewer

<p align="center">
  <img src="assets/icon/icon.png" alt="DAViewer" width="160" />
</p>

**Language:** English · [中文](README.md)

DeviantArt's official client is no longer maintained. DAViewer is a third-party client built on [DAKit](https://github.com/redtidev1918/DAKit) for Android, macOS, and Windows.

📖 Full documentation: <https://redtidev1918.github.io/DAViewer/>

[![GitHub license](https://img.shields.io/github/license/redtidev1918/DAViewer?style=flat)](LICENSE) [![GitHub release](https://img.shields.io/github/v/release/redtidev1918/DAViewer?style=flat)](https://github.com/redtidev1918/DAViewer/releases) [![Platforms](https://img.shields.io/badge/platform-Android%20%7C%20macOS%20%7C%20Windows-blue?style=flat)](https://github.com/redtidev1918/DAViewer/releases) [![Docs](https://img.shields.io/badge/Docs-documentation-6366f1?style=flat-square)](https://redtidev1918.github.io/DAViewer/)

## Download

Grab your platform's file from [Releases](https://github.com/redtidev1918/DAViewer/releases):

- **Android**: `DAViewer-v<version>.apk`
- **Windows**: `DAViewer-v<version>-windows.zip`
- **macOS**: `DAViewer-v<version>-macos-unsigned-preview.zip`

On macOS, right-click the app in Finder and choose **Open** the first time.

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
flutter run -d macos     # macOS
flutter run -d android   # Android
flutter run -d windows   # Windows
```

The app depends on published DAKit packages — versions in [pubspec.yaml](pubspec.yaml), app/SDK boundary in [Architecture](docs/en/architecture.md).

Ordinary users need no OAuth app. To use your own, pass `--dart-define=DAKIT_CLIENT_ID=YOUR_PUBLIC_CLIENT_ID` and add `dakit://oauth/callback` to its whitelist.

## Proxy

The network path is taken from Settings → Proxy first, then the system proxy, then `https_proxy` / `http_proxy` / `all_proxy`. Use the HTTP/Mixed port your proxy app shows — there is no fixed value. Full rules in [Networking and proxy](docs/en/networking.md).

## Release

Pushing a `v*` tag creates a Release, with notes taken from `RELEASE_NOTES.md`. To cut one, use Actions → **Release** → Run workflow and pick `patch` / `minor` / `major`, or an exact version.

```shell
flutter build apk --release          # Android APK, needs android/key.properties
flutter build macos --release        # macOS
flutter build windows --release      # Windows
```

Signing and the pinned toolchain are in [Build notes](docs/en/build.md).

## Login issues

- **The page did not open or is stuck**: tap "Done" at the top right and reopen it; you can run the connectivity test first.
- **Mature content**: Settings → DeviantArt account settings → Mature content settings.
- **First sign-in on macOS**: the system asks for keychain permission once — choose Allow.

State and recovery rules are in [Authentication and session recovery](docs/en/authentication.md).

## Contributing

Issues, PRs, and docs are welcome — see [CONTRIBUTING.md](CONTRIBUTING.md). After a change, run `dart format lib test`, `flutter analyze`, and `flutter test`. Security reports go to [SECURITY.md](SECURITY.md).

## Notes

- DAViewer is a third-party client and is not affiliated with DeviantArt.
- Sign-in uses DeviantArt's official page; the client does not store a `client_secret`.

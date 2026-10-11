# Contributing to DAViewer

DAViewer is a DeviantArt client built on [DAKit](https://github.com/redtidev1918/DAKit). You can contribute bug reports, fixes, features, translations, and documentation.

## Before you start

Search existing [issues](https://github.com/redtidev1918/DAViewer/issues) and pull requests. Report security issues through [SECURITY.md](SECURITY.md).

DAKit owns OAuth, official API mapping, domain models, transfers, and generic private-protocol parsing in `dakit_web`. DAViewer owns WebView sessions, source selection, caching, navigation, and presentation. For an SDK change, submit it upstream and publish the package before updating this app's dependency. See [Architecture](docs/en/architecture.md).

## Development setup

Install Flutter 3.47.1, then run:

```shell
flutter doctor
flutter pub get
flutter devices
flutter run -d <device-id>
```

For platform tools, signing, and build proxies, see [Building and releasing](docs/en/build.md). Flutter, Gradle, AGP, Kotlin, and `flutter_inappwebview` are pinned; verify Android and macOS compatibility before upgrading them.

## Project structure

| Path | Responsibility |
| --- | --- |
| `lib/app/` | App shell, theme, router |
| `lib/core/auth/` | OAuth state, web-session storage, verification, login bridge |
| `lib/core/data/` | Data access, source policy, repository request gate |
| `lib/core/runtime/` | DAKit composition |
| `lib/core/network/` | Proxy selection, HTTP routing, WebView proxy configuration |
| `lib/core/feed/` | Feed request state and pagination |
| `lib/core/history/`, `lib/core/search/` | Visit history, search history, tag interests |
| `lib/core/diagnostics/`, `lib/core/notice/` | Logging, error reports, notices |
| `lib/core/l10n/`, `lib/core/settings/`, `lib/core/theme/` | Translations and persisted preferences |
| `lib/features/` | Screens and feature providers |
| `lib/shared/widgets/` | Artwork cards and shared UI |
| `android/`, `macos/`, `windows/` | Platform projects |
| `test/` | Unit and widget tests |
| `docs/`, `docs/en/` | Chinese and English documentation |

## Making a change

1. Create a focused branch from `main`.
2. Make the change and add regression coverage when behavior changes.
3. For Dart changes, run `dart format lib test`, `flutter analyze`, and `flutter test`. CI checks formatting without rewriting files.
4. Open a pull request describing the problem, resulting behavior, and validation. Include device evidence when the change depends on WebView, Keychain, or native gestures.

Keep user-facing strings in `lib/core/l10n/app_strings.dart` in Chinese and English. Treat feed artwork as sparse: hydrate detail-only fields through the repository and merge through `ArtworkStore`, preserving richer cached data. At 1x zoom, horizontal gestures may switch artwork; once zoomed, the image viewer owns panning and outer navigation recognizers must be disabled.

Documentation changes should keep corresponding Chinese and English guides aligned. Check relative links and documented commands against repository configuration. Download pages are generated: edit `.github/scripts/update_download_page.py` or `docs/download-preview.md`, then regenerate them rather than patching the output alone. Preserve the verification scope of historical audit and regression records.

## CI and releases

CI runs analysis, formatting checks, tests, and release-note validation on PRs and pushes to `main`. The Release workflow calls ReleaseGraph with dry-run enabled for PRs; published assets are built for Android, macOS, and Windows. Release versioning uses release-please, and Chinese release bodies live in `.github/release-notes/<version>.md`.

See [Building and releasing](docs/en/build.md) for workflow inputs and [Release gate](docs/release-gate.md) for manual acceptance requirements. Report a bug with its app version, platform, reproduction steps, and relevant redacted diagnostics.

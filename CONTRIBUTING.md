# Contributing to DAViewer

Thanks for wanting to help! DAViewer is a community client for DeviantArt built
on [DAKit](https://github.com/redtidev1918/DAKit). Contributions of any size are
welcome — bug reports, fixes, features, translations, and documentation.

## Before you start

- **SDK vs app**: DAViewer is the app; [DAKit](https://github.com/redtidev1918/DAKit)
  is the SDK it depends on. If a change belongs in the SDK (API adapters, OAuth,
  domain models, transfers), open the PR over there and publish it first, then
  bump the dependency here.
- Search existing [issues](https://github.com/redtidev1918/DAViewer/issues) and
  PRs before opening a new one.
- For security issues, see [SECURITY.md](SECURITY.md) and do **not** file them
  publicly.

## Development setup

1. Install Flutter 3.47.1 (the project pins this version).
2. `flutter pub get`
3. Run `dart format lib test`, `flutter analyze`, and `flutter test` before
   committing — all must pass.
4. For a full build, see [Build notes](docs/build.md).

> The project deliberately pins `flutter_inappwebview 6.1.5` and specific
> Gradle/AGP/Kotlin versions (see the [toolchain pin](docs/build.md#toolchain-pin)).
> Do not upgrade these without verifying the toolchain compatibility.

## Project structure

```text
lib/
  main.dart                    App entry, proxy injection, ProviderScope
  app/                         AppShell, theme, router
  core/
    auth/                      Sign-in state, session restore, logout, WebView OAuth bridge
    data/                      Unified data access layer (official API + web fallback)
    diagnostics/               File logging, global error capture
    downloads/                 Completed-download shared-storage saver
    feed/                      Paged feed controller
    l10n/                      Chinese/English strings and language state
    network/                   Proxy detection, open-in-browser, dynamic proxy Dio
    runtime/                   DAKit composition root
    search/                    Search history persistence
    settings/                  Persisted user preferences (language, theme)
    theme/                     Theme mode controller
  features/
    web_login/                 Web-session commit and OAuth login page
    home/                      Home (native For you / Daily feeds)
    watched/                   Watched feed (first-class "following" tab + avatar strip)
    search/                    Search
    artwork/                   Artwork detail, media playback, download, favourite
    artist/                    Artist profile, gallery, favourites, watch
    favourites/                Current account favourites
    watching/                  Watched users list
    downloads/                 Download list
    notifications/             Message center + local read-state store
    settings/                  Settings, proxy, language, theme, logs, about
    diagnostics/               Log & diagnostics page
    splash/                    Splash screen
  shared/widgets/              Shared artwork card, empty/error states, timestamps
android/
macos/
windows/
test/
```

## Workflow

1. Fork the repository and create a branch from `main`.
2. Make your change. Keep commits focused and descriptive.
3. `flutter analyze` and `flutter test` locally.
4. Open a pull request. Explain **what** changed and **why**.

> Pushing to `main` runs the full CI pipeline (quality checks plus Android, macOS,
> and Windows builds). For documentation-only commits, add `[skip ci]` to the
> commit message (e.g. `docs: fix typo [skip ci]`) to skip CI. A GitHub Release
> is created only when a `v*` tag is pushed (via the manual Release workflow), so
> ordinary pushes never release by themselves.

## Style

- Follow the existing code style; run `dart format lib test` before committing.
- Keep user-facing strings in `lib/core/l10n/app_strings.dart` (Chinese + English).
- Treat list-endpoint artwork as potentially sparse. Hydrate detail-only fields
  through the canonical repository and merge them through `ArtworkStore`; never
  let a later feed refresh erase richer cached data.
- At 1x zoom, horizontal gestures may navigate between artworks. Once zoomed,
  the image viewer owns both axes and outer navigation recognizers must be off.
- Prefer small, reviewable PRs over large, mixed ones.

## Getting help

Open an issue with the `question` label, or start a discussion. Maintainers and
the community will help you get unblocked.

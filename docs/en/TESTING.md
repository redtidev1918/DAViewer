---
title: Testing
description: DAViewer testing policy — verification layers, the local quality gate, CI checks, and how they relate to device acceptance.
---

# Testing

**Language / 语言:** [中文](/TESTING.md) · English

This page is the canonical entry point for DAViewer's testing strategy: how verification layers, the local quality gate, CI checks, and device acceptance relate to each other. Release acceptance criteria live in the [Release gate](release-gate.md); past defects and their evidence live in the [Regression catalog](../regressions/README.md). **Passing automated tests never replaces device verification.**

## Verification layers

| Layer | Scope | How it runs |
| --- | --- | --- |
| L1 local quality gate | Before every Dart commit | Commands below, identical to CI |
| L2 unit / widget tests | `test/` (`*_test.dart`) | `flutter test`; no `integration_test/` yet |
| L3 CI quality checks | PRs and pushes to `main` | `.github/workflows/ci.yml` |
| L4 SDK joint verification | PRs touching `lib/**`, `test/**`, `pubspec.*`, build scripts | `.github/workflows/sdk-integration.yml` |
| L5 three-platform candidate builds | PRs and releases | ReleaseGraph quality matrix; Windows/macOS candidates are actually launched for smoke checks |
| L6 device acceptance | Release candidates | Executed and recorded manually per the [Release gate](release-gate.md) |
| L7 regression evidence | Behavior changes | New or updated entries in the [Regression catalog](../regressions/README.md) |

## L1 local quality gate

```shell
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test --dart-define=DAVIEWER_VERSION=0.7.0
```

`DAVIEWER_VERSION` takes the current value from `.release-please-manifest.json` (CI injects it from the same manifest). Omitting it skews the version-dependent update-check test; the automatic update check requires this define, so it cannot be dropped. Full build commands are in [Build notes](build.md).

## Test authoring rules

1. **Protocol fixtures must come from real evidence.** For any parsing logic that consumes an external API, web protocol, or third-party data structure, test samples must be taken from independently obtained real captures (record when and where each was captured); never reverse-engineer them from the current implementation. This is a permanent rule in AGENTS.md, adopted after the `@publicSession` key-name incident.
2. **Fixtures go through the production write path.** Persistence and recovery tests must write through production code and read back through it. The lesson is [REG-026](../regressions/026-web-session-restore-decode.md): store tests bypassed the `read()` composition point with a bare JSON helper, and 586 green tests never noticed the recovery path had been broken.
3. **Clean up timers in widget tests.** When the object under test owns a Timer or periodic callback, cancel it explicitly in `tearDown` to avoid testWidgets leaks that hang the suite.
4. **Behavior changes require a regression test.** For a defect fix, first write the test that fails against the old code, then fix it. Record the evidence boundary (known vs. unknown) in the regression entry using the established vocabulary.
5. **User-visible strings** go in `lib/core/l10n/app_strings.dart` in both Chinese and English, with a matching update to `app_strings_test.dart`.

## L3 CI quality checks (ci.yml)

- `flutter analyze` and `dart format` checks (CI checks but never rewrites files).
- `flutter test` with the manifest-version define.
- Chinese release-notes check for the current manifest version: `.github/release-notes/<version>.md` must exist and contain the「本次更新」section and Chinese text.
- Release asset naming: `scripts/build-release` and `.release-policy.yml` only allow asset names of the form `DAViewer-v*`.

## L4 SDK joint verification (sdk-integration.yml)

Runs automatically on PRs that change `lib/**`, `test/**`, `pubspec.yaml`, `pubspec.lock`, or `scripts/build-release`: it checks out DAKit at a pinned SHA, runs the DAKit workspace checks first, then points the app dependencies at that SDK source and runs the full analyze/format/test suite, and finally builds three-platform candidate packages (the Windows/macOS candidates are actually launched).

Changing DAKit: fix and publish new package versions in the DAKit repository first, then update this repository's dependencies and lockfile, then re-run this layer; production builds refuse to carry a candidate Git override. See the release process in [Build notes](build.md).

## L6 device acceptance

Follow the path table in the [Release gate](release-gate.md): sign-in and recovery, recommendations, web session, WebView, notices, favourite notifications, proxies, content and downloads. Changes that depend on WebView, Keychain, or native gestures must ship device evidence (required by [CONTRIBUTING](https://github.com/redtidev1918/DAViewer/blob/main/CONTRIBUTING.md)). The repository currently has no `integration_test/` directory; if one is introduced, update this page, CI, and the release gate together.

## Evidence vocabulary

Regression and acceptance conclusions reuse the repository's established vocabulary — never invent a second set:

- Regression entries: `Verified` / `Partial` / `Unverified` / `Blocked by Environment` (defined in the [Regression catalog](../regressions/README.md)).
- Release gate: `Code Verified` / `CI Verified` / `Release Verified` / `Android Verified` / `Original Incident Verified` (from the session-recovery archive).

Passing tests supports at most `Code Verified`; `Android Verified` and `Original Incident Verified` can only come from real devices and retained-account evidence.

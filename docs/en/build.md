# Building and releasing

Language / 语言: [中文](../build.md) · English

Use the same toolchain locally as in CI. Version and release configuration live in `pubspec.yaml`, `.release-please-manifest.json`, `.release-policy.yml`, and `.github/workflows/release.yml`.

## Development environment

Install Flutter 3.47.1 and the build tools for your target. Android needs the Android SDK; build macOS on macOS and Windows on Windows.

```shell
flutter doctor
flutter pub get
flutter devices
flutter run -d <device-id>
```

Desktop device IDs are `macos` and `windows`. For Android, use an ID from `flutter devices`. The app includes a public OAuth client ID. To use your own app, add `--dart-define=DAKIT_CLIENT_ID=YOUR_PUBLIC_CLIENT_ID` and register `dakit://oauth/callback`.

## Pinned toolchain

| Component | Pinned version | Configuration |
| --- | --- | --- |
| Flutter | `3.47.1` | `.github/workflows/ci.yml`, `.release-policy.yml` |
| Android Gradle Plugin | `8.13.2` | `android/settings.gradle.kts` |
| Gradle | `8.14.2` | `android/gradle/wrapper/gradle-wrapper.properties` |
| Kotlin | `2.2.20` | `android/settings.gradle.kts` |
| flutter_inappwebview | `6.1.5` (exact) | `pubspec.yaml` |

When upgrading Flutter or the WebView plugin, verify compilation of both the Android and macOS sub-packages.

## Validation and builds

For Dart changes, run the same quality checks as CI before committing:

```shell
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

Run release builds on the corresponding platform:

```shell
flutter build apk --release      # Requires android/key.properties
flutter build macos --release
flutter build windows --release
```

Android release builds require the upload keystore and `android/key.properties`; missing configuration fails the build. CI uses `KEYSTORE_B64` and `KEYSTORE_PROPERTIES`. A PR dry-run without signing secrets can build a debug APK, but that APK cannot serve as a production release.

The current macOS script runs a Flutter release build and archives `DAViewer.app`. It has no stable preview-certificate import, Developer ID signing, or notarization step. The artifact keeps the `macos-unsigned-preview` name. Local ad-hoc signing or a missing TeamIdentifier is an environment limit. Verify Keychain access after upgrades on a real device; signing identity continuity is not guaranteed.

## Release workflow

`.github/workflows/release.yml` calls ReleaseGraph. `.release-policy.yml` selects release-please versioning, three-platform builds, asset validation, and retention. PRs run in dry-run mode; pushes to `main`, scheduled runs, and manual dispatch enter the release workflow. The current workflow has no `v*` tag-push trigger.

1. Manage version changes through release-please and check `pubspec.yaml` against `.release-please-manifest.json`.
2. Write Chinese notes in `.github/release-notes/<version>.md`, including a 本次更新 section. CI checks that the current manifest version has a notes file containing Chinese.
3. Pass quality, build, and asset checks. Manual acceptance requirements are in the [Release gate](../release-gate.md) (Chinese).
4. After publishing, the script updates both download pages and dispatches Pages deployment. `CHANGELOG.md` and `RELEASE_NOTES.md` retain past changes.

For a manual run, open Actions → **Release** → Run workflow:

| Input | Purpose |
| --- | --- |
| `version` | Existing version; leave blank to read the manifest |
| `dry_run` | Build and validate without publishing |
| `force` | Rerun a healthy version |
| `repair` | Repair the current incomplete version |
| `stage` | Recovery stage label; defaults to `all` |

Asset names are `DAViewer-v<version>.apk`, `DAViewer-v<version>-windows.zip`, and `DAViewer-v<version>-macos-unsigned-preview.zip`. Retention keeps one stable release, one prerelease, and two failed drafts. Release-page retention does not describe source-history retention.

## Build proxies

Configure build-tool proxies separately from the app proxy. Ports `7890` and `7892` below are examples; replace them with the HTTP/Mixed port shown by your proxy app.

Bash / zsh:

```bash
export http_proxy=http://127.0.0.1:7890
export https_proxy=http://127.0.0.1:7890
export no_proxy=localhost,127.0.0.1
flutter pub get
```

PowerShell:

```powershell
$env:http_proxy = 'http://127.0.0.1:7890'
$env:https_proxy = 'http://127.0.0.1:7890'
$env:no_proxy = 'localhost,127.0.0.1'
flutter pub get
```

Gradle runs on the JVM. Set JVM proxy properties explicitly when Android toolchain downloads need a proxy:

```bash
export GRADLE_OPTS="-Dhttp.proxyHost=127.0.0.1 -Dhttp.proxyPort=7892 -Dhttps.proxyHost=127.0.0.1 -Dhttps.proxyPort=7892"
flutter build apk --debug
```

```powershell
$env:GRADLE_OPTS = '-Dhttp.proxyHost=127.0.0.1 -Dhttp.proxyPort=7892 -Dhttps.proxyHost=127.0.0.1 -Dhttps.proxyPort=7892'
flutter build apk --debug
```

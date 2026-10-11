# 构建与发布

语言 / Language：中文 · [English](en/build.md)

本地构建使用与 CI 相同的工具链。版本和发布规则分别见 `pubspec.yaml`、`.release-please-manifest.json`、`.release-policy.yml` 与 `.github/workflows/release.yml`。

## 开发环境

安装 Flutter 3.47.1，并准备目标平台的构建工具。Android 使用 Android SDK；macOS 构建在 macOS 上进行；Windows 构建在 Windows 上进行。

```shell
flutter doctor
flutter pub get
flutter devices
flutter run -d <设备ID>
```

桌面设备 ID 为 `macos` 或 `windows`；Android 使用 `flutter devices` 列出的设备 ID。应用默认带有公开 OAuth client ID。使用自己的应用时，附加 `--dart-define=DAKIT_CLIENT_ID=你的_PUBLIC_CLIENT_ID`，并注册回调 `dakit://oauth/callback`。

## 固定工具链

| 组件 | 仓库固定版本 | 配置位置 |
| --- | --- | --- |
| Flutter | `3.47.1` | `.github/workflows/ci.yml`、`.release-policy.yml` |
| Android Gradle Plugin | `8.13.2` | `android/settings.gradle.kts` |
| Gradle | `8.14.2` | `android/gradle/wrapper/gradle-wrapper.properties` |
| Kotlin | `2.2.20` | `android/settings.gradle.kts` |
| flutter_inappwebview | `6.1.5`（精确版本） | `pubspec.yaml` |

升级 Flutter 或 WebView 插件时，同时验证 Android 与 macOS 子包的编译兼容性。

## 验证与构建

Dart 改动提交前运行与 CI 相同的质量检查：

```shell
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

在对应平台执行 release 构建：

```shell
flutter build apk --release      # 需要 android/key.properties
flutter build macos --release
flutter build windows --release
```

Android release 构建需要上传密钥库与 `android/key.properties`，缺少配置时构建会失败。CI 使用 `KEYSTORE_B64` 与 `KEYSTORE_PROPERTIES`；PR 的 dry-run 在没有签名机密时可构建 debug APK，但该包不能作为正式发布包。

macOS 当前脚本执行 Flutter release 构建后压缩 `DAViewer.app`，没有导入稳定预览证书、Developer ID 签名或公证步骤。产物名保留 `macos-unsigned-preview`。本地 ad-hoc 签名或缺少 TeamIdentifier 属于环境限制；升级后的 Keychain 授权表现需实机验证，不能承诺签名身份连续性。

## 发布流程

`.github/workflows/release.yml` 调用 ReleaseGraph；`.release-policy.yml` 选择 release-please 版本管理、三平台构建、资产检查和保留策略。PR 执行 dry-run，`main` 推送、定时任务和手动触发进入发布流程。当前工作流没有 `v*` tag 推送触发器。

1. 通过 release-please 管理版本变更，核对 `pubspec.yaml` 与 `.release-please-manifest.json`。
2. 在 `.github/release-notes/<版本>.md` 中编写中文正文，包含「本次更新」。CI 检查当前 manifest 版本的文件是否存在并含中文。
3. 通过质量检查、构建和资产验证。发布前人工验收见 [发布门禁](release-gate.md)。
4. 发布后，脚本更新中英文下载页并触发 Pages 部署。`CHANGELOG.md` 与 `RELEASE_NOTES.md` 保留历史更新记录。

手动操作入口为 Actions → **Release** → Run workflow：

| 参数 | 用途 |
| --- | --- |
| `version` | 已有版本号；留空读取 manifest |
| `dry_run` | 构建和验证，不发布 |
| `force` | 重新执行已健康的版本 |
| `repair` | 修复当前不完整版本 |
| `stage` | 恢复阶段标签，默认 `all` |

发布资产名为 `DAViewer-v<版本>.apk`、`DAViewer-v<版本>-windows.zip` 和 `DAViewer-v<版本>-macos-unsigned-preview.zip`。保留策略分别保留一个 stable 和一个 prerelease，以及两个失败草稿；不要把发布页保留数量当作源码历史。

## 构建代理

构建工具的代理与应用内代理分开配置。以下命令中的 `7890` 和 `7892` 都是示例，请替换成代理软件显示的 HTTP/Mixed 端口。

Bash / zsh：

```bash
export http_proxy=http://127.0.0.1:7890
export https_proxy=http://127.0.0.1:7890
export no_proxy=localhost,127.0.0.1
flutter pub get
```

PowerShell：

```powershell
$env:http_proxy = 'http://127.0.0.1:7890'
$env:https_proxy = 'http://127.0.0.1:7890'
$env:no_proxy = 'localhost,127.0.0.1'
flutter pub get
```

Gradle 在 JVM 中运行。Android 工具链下载需要代理时，显式设置 JVM 代理属性：

```bash
export GRADLE_OPTS="-Dhttp.proxyHost=127.0.0.1 -Dhttp.proxyPort=7892 -Dhttps.proxyHost=127.0.0.1 -Dhttps.proxyPort=7892"
flutter build apk --debug
```

```powershell
$env:GRADLE_OPTS = '-Dhttp.proxyHost=127.0.0.1 -Dhttp.proxyPort=7892 -Dhttps.proxyHost=127.0.0.1 -Dhttps.proxyPort=7892'
flutter build apk --debug
```

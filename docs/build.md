# DAViewer 构建说明

> English: [DAViewer build notes](/en/build.md)

README 放不下、又不适合省略的工具链、发版与构建代理细节。

## 工具链版本固定

Flutter 3.47 默认使用 AGP 9.1.0，但稳定版 `flutter_inappwebview`（6.1.5）的 Android 子包仍引用 `proguard-android.txt`（AGP 9 已移除该文件），其 beta 版 macOS 子包在 Swift 6 下也无法编译。因此本项目固定以下工具链（均满足 Flutter 3.47 的 Gradle ≥ 8.14 / Kotlin ≥ 2.2.20 下限）：

| 组件 | 版本 | 说明 |
| --- | --- | --- |
| Android Gradle Plugin | `8.13.2` | 8.x 保留 `proguard-android.txt`，且支持 compileSdk 36 |
| Gradle | `8.14.2` | Flutter 3.47 下限为 8.14 |
| Kotlin | `2.2.20` | Flutter 3.47 下限为 2.2.20 |
| flutter_inappwebview | `6.1.5`（精确） | 稳定版；不要升到 `6.2.0-beta`（macOS 构建失败） |

这些值位于 `android/settings.gradle.kts`、`android/gradle/wrapper/gradle-wrapper.properties` 与 `pubspec.yaml`。升级插件或 Flutter 之前，请先确认 `flutter_inappwebview` 的 Android/macOS 子包与新 AGP/Swift 工具链兼容。

## 发布契约

- 推送到 `main` 触发 CI 质量检查与 Android/macOS/Windows 构建；推送 `v*` tag 会创建 GitHub Release，其说明取自 `RELEASE_NOTES.md` 中对应的面向用户章节。缺少该章节会**阻止**发版，而不是退化成提交信息或内部实现说明。
- 发布用 APK 始终使用上传密钥库签名（CI 机密 `KEYSTORE_B64` / `KEYSTORE_PROPERTIES`）；缺少本地 `android/key.properties` 的 release 构建会**故意失败**，从而不可能用 debug 签名的 APK 覆盖此前上传签名的发布版。
- macOS 发布 tag 需要私有预览证书机密。CI 用该稳定自签名身份签名、重新应用仓库内声明的 entitlements、校验两种 CPU 架构，并让应用保持运行 8 秒完成启动冒烟测试。非发布构建可回退到 ad-hoc 签名。产物仍带 `macos-unsigned-preview` 标记，因为预览身份不是 Apple Developer ID，包也未公证。
- 项目**不购买 Apple Developer Program**；稳定签名与公证明确不在发布范围内。
  本地 `ad-hoc / 无 TeamIdentifier` 是接受的环境限制，不作为 Release Gate
  阻塞项。

### 一键发版

Actions → **Release** → Run workflow → 选择 `patch` / `minor` / `major`（或具体版本）→ 运行。它会升版本、提交、推 tag，CI 随后构建并发布。

本地验证构建：

```shell
flutter build apk --release          # Android APK（需要 android/key.properties）
flutter build macos --release        # macOS 应用
flutter build windows --release      # Windows 应用
```

## 构建走代理

`flutter pub get` 使用 Dart 的 HTTP 客户端，不读 Git 代理配置：

```shell
export http_proxy=http://127.0.0.1:7890
export https_proxy=http://127.0.0.1:7890
# 或使用一个通用代理（大小写变量都受支持）：
# 7892 只是示例，请替换成你自己代理的 HTTP/Mixed 端口。
# export all_proxy=http://127.0.0.1:7892
export no_proxy=localhost,127.0.0.1
flutter pub get
```

Gradle Wrapper 运行在 JVM 上，不保证读取 `all_proxy`。当 Android 工具链下载需要代理时，显式传入 JVM 代理属性：

```shell
# 把 7892 替换成代理应用实际显示的 HTTP/Mixed 端口。
export GRADLE_OPTS="-Dhttp.proxyHost=127.0.0.1 -Dhttp.proxyPort=7892 -Dhttps.proxyHost=127.0.0.1 -Dhttps.proxyPort=7892"
flutter build apk --debug
```

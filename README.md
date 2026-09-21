# DAViewer

<p align="center">
  <img src="assets/icon/icon.png" alt="DAViewer" width="160" />
</p>

**语言 / Language:** 中文 · [English](README.en.md)

> **基于 DAKit 的开源 DeviantArt 客户端，支持 Android / macOS / Windows。**

DeviantArt 官方客户端已经停止维护。DAViewer 是基于 [DAKit](https://github.com/redtidev1918/DAKit) 的第三方客户端，支持 Android、macOS 和 Windows。

📖 [完整文档](https://redtidev1918.github.io/DAViewer/)

[![GitHub license](https://img.shields.io/github/license/redtidev1918/DAViewer?style=flat)](LICENSE) [![GitHub release](https://img.shields.io/github/v/release/redtidev1918/DAViewer?style=flat)](https://github.com/redtidev1918/DAViewer/releases) [![Platforms](https://img.shields.io/badge/platform-Android%20%7C%20macOS%20%7C%20Windows-blue?style=flat)](https://github.com/redtidev1918/DAViewer/releases) [![Docs](https://img.shields.io/badge/Docs-文档站点-6366f1?style=flat-square)](https://redtidev1918.github.io/DAViewer/)

## 下载

从 [Releases](https://github.com/redtidev1918/DAViewer/releases) 取对应平台的文件：

- **Android**：`DAViewer-v<版本>.apk`
- **Windows**：`DAViewer-v<版本>-windows.zip`
- **macOS**：`DAViewer-v<版本>-macos-unsigned-preview.zip`

macOS 首次打开需要在 Finder 里右键点 App，选「打开」。

## 截图

<table align="center">
  <tr>
    <td align="center"><img src="docs/screenshots/home_feed.jpg" width="200" /><br /><sub>首页推荐</sub></td>
    <td align="center"><img src="docs/screenshots/artwork_detail.jpg" width="200" /><br /><sub>作品详情</sub></td>
    <td align="center"><img src="docs/screenshots/related_works.jpg" width="200" /><br /><sub>相关推荐</sub></td>
  </tr>
</table>

## 功能

- **登录**：内嵌网页打开 DeviantArt 官方登录页，支持 DeviantArt / Google / Apple / Facebook
- **首页**：推荐（个性化推荐流）、每日精选、关注动态
- **搜索**：边输边出结果 + 历史记录；粘贴链接直达作品或作者
- **作品详情**：滑动切换前后作品，相邻作品预加载；双指缩放、多图分页
- **访问历史**：本地记录最近浏览的作品，最多 200 条，可在搜索页右上角进入并清空
- **媒体**：视频最高画质、自动循环、可拖动、失败重试；GIF 角标
- **相关内容**：更多类似作品、相似画师、收藏集、作者更多作品
- **作者**：资料、画廊（可搜索）、自定义画集、收藏夹、关注
- **社交**：收藏（含收藏态）、关注/取关、关注列表、通知
- **下载**：原图权限不足时保存最高画质预览；长按图片可单张下载，完成后可打开文件或文件夹
- **分享**：作品、画师、画册、收藏集、标签调用系统原生分享
- **设置**：浅色 / 深色 / 跟随系统，中英双语，清除缓存，检查更新
- **诊断**：一键生成预填好的 GitHub Issue

## 开发

```shell
flutter pub get
flutter run -d macos     # macOS
flutter run -d android   # Android
flutter run -d windows   # Windows
```

依赖已发布的 DAKit 包，版本见 [pubspec.yaml](pubspec.yaml)；应用与 SDK 的边界见 [架构说明](docs/architecture.md)。

普通用户不用注册 OAuth 应用。要用自己的 OAuth 应用，加 `--dart-define=DAKIT_CLIENT_ID=你的_PUBLIC_CLIENT_ID`，并在应用白名单里加 `dakit://oauth/callback`。

## 代理

网络路径依次取「设置 → 网络代理」、系统代理、`https_proxy` / `http_proxy` / `all_proxy`。端口填代理软件显示的 HTTP/Mixed 端口，没有固定值。完整规则见 [网络与代理](docs/networking.md)。

## 发布

打 `v*` 标签会创建 Release，说明取自 `RELEASE_NOTES.md`。要出包走 Actions → **Release** → Run workflow，选 `patch` / `minor` / `major` 或填版本号。

```shell
flutter build apk --release          # Android APK，需 android/key.properties
flutter build macos --release        # macOS
flutter build windows --release      # Windows
```

签名与工具链见 [构建说明](docs/build.md)。

## 登录问题

- **登录页打不开或卡住**：点右上角「完成」重开；登录前可以先跑一次连通性测试。
- **成人内容**：「设置 → DeviantArt 账号设置 → 成人内容设置」。
- **macOS 首次登录**：系统会问一次钥匙串权限，选「允许」。

状态与恢复规则见 [登录与会话说明](docs/authentication.md)。

## 参与

Issue、PR、文档都欢迎，见 [CONTRIBUTING.md](CONTRIBUTING.md)。改动后跑 `dart format lib test`、`flutter analyze`、`flutter test`；安全问题走 [SECURITY.md](SECURITY.md)。

## 文档

README 只讲怎么开始；完整内容在[文档站](https://redtidev1918.github.io/DAViewer/)：

| 你想做什么 | 文档 |
| --- | --- |
| 下载安装包 | [下载页](https://redtidev1918.github.io/DAViewer/download.md) |
| 登录与常见问题 | [登录与会话](docs/authentication.md) |
| 网络与代理 | [网络与代理](docs/networking.md) |
| 看应用与 SDK 的边界 | [架构说明](docs/architecture.md) |
| 本地构建、发版 | [构建说明](docs/build.md) |

## 致谢

DAViewer 建立在 [DAKit](https://github.com/redtidev1918/DAKit) 与 [Flutter](https://flutter.dev) 之上；
WebView、状态管理、路由、图片缓存、视频播放与富文本分别由 `flutter_inappwebview`、`flutter_riverpod`、
`go_router`、`cached_network_image`、`chewie` / `video_player`、`flutter_html` 承担，完整清单见
[pubspec.yaml](pubspec.yaml)。网页私有接口的解析参考了 [gallery-dl](https://github.com/mikf/gallery-dl) 与
[deviantart.ts](https://www.npmjs.com/package/deviantart.ts)。

## 说明

- DAViewer 是第三方客户端，与 DeviantArt 无隶属关系。
- 登录使用 DeviantArt 官方页面，客户端不保存 `client_secret`。

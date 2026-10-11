# DAViewer

<p align="center">
  <img src="assets/icon/icon.png" alt="DAViewer" width="128" />
</p>

DAViewer 是一个开源的 DeviantArt 第三方客户端，支持 Android、Windows 和 macOS。你可以浏览作品、发现画师、收藏喜欢的内容，并下载允许保存的图片。

DAViewer 不是 DeviantArt 官方应用，与 DeviantArt 没有隶属或合作关系。

**[下载最新版本](https://github.com/redtidev1918/DAViewer/releases)** · [文档站](https://redtidev1918.github.io/DAViewer/) · [首次使用](#首次使用) · [常见问题](#常见问题)

[![GitHub release](https://img.shields.io/github/v/release/redtidev1918/DAViewer?style=flat)](https://github.com/redtidev1918/DAViewer/releases) [![GitHub license](https://img.shields.io/github/license/redtidev1918/DAViewer?style=flat)](LICENSE)

**语言 / Language:** 中文 · [English](README.en.md)

## 截图

<p align="center">
  <img src="docs/screenshots/home_feed.jpg" width="30%" alt="首页推荐" />
  <img src="docs/screenshots/artwork_detail.jpg" width="30%" alt="作品详情" />
  <img src="docs/screenshots/related_works.jpg" width="30%" alt="相关作品与原图下载" />
</p>

<p align="center"><sub>首页推荐 · 作品详情 · 相关作品与原图下载</sub></p>

## 你能做什么

### 浏览与发现

- **推荐**：按你的 DeviantArt 网页会话生成个性化推荐流。
- **每日精选**：DeviantArt 的当日精选。
- **关注动态**：集中查看你关注的画师的新作品，顶部可以切换画师。
- **搜索与标签**：输入即出结果，可在作品和用户之间切换；输入 `#标签` 直达标签页，作品结果可按默认或最新排序。
- **打开链接**：首页右上角的链接按钮，粘贴 DeviantArt 作品或画师链接即可跳转。

### 作品浏览

- **大图与多图**：全屏查看、双击放大、多图分页，左右滑动切换相邻作品。
- **视频与动图**：视频自动播放并循环，可拖动进度、调节音量和播放速度。
- **作品信息**：标题、作者、描述、标签，以及原图是否可下载和文件大小。
- **更多类似作品**：在作品页继续发现相关作品，可随时刷新。

### 画师与互动

- **画师主页**：资料、作品、收藏的作品、日志和自定义画集，画廊内可直接搜索。
- **关注**：在画师主页关注或取消关注，并在关注列表里查看已关注的画师。
- **收藏**：在作品页收藏，底部「收藏」标签浏览自己的收藏和收藏集。
- **通知**：官方消息列表，未读数量显示在首页铃铛上。

### 下载作品

- **原图优先**：作品可下载时直接保存原图，多图作品可以一次下载全部页面。
- **受限时降级**：原图需要付费、受权限限制或已失效时，只有纯图片作品会保存当前展示的图片（这不是原图）；含视频的作品不会降级。
- **下载管理**：底部「下载」标签查看进度，传输中可暂停、继续、取消和重试，完成后可以打开文件。

### 个性化与工具

- **主题与语言**：浅色 / 深色 / 跟随系统，中英文界面。
- **网络代理**：可以手动填写代理地址，也可以自动使用系统代理。
- **访问历史**：本机记录最近打开的作品，最多 200 条，可一键清空。
- **检查更新**：发现新版本时提示，并在浏览器中打开发布页。

浏览、搜索、收藏、关注和下载都需要登录 DeviantArt 账号；未登录时只有登录页、设置和访问历史可用。

## 下载与安装

安装包都在 [Releases](https://github.com/redtidev1918/DAViewer/releases) 页面，按平台选择：

- **Android**：下载 `DAViewer-v<版本>.apk`，打开安装。需要 Android 7.0 或更高；系统提示安装未知来源应用时，按提示允许。
- **Windows**：下载 `DAViewer-v<版本>-windows.zip`，解压后运行 `daviewer.exe`。请保留整个解压后的文件夹，只把 `daviewer.exe` 单独移走会导致应用无法启动。
- **macOS**：下载 `DAViewer-v<版本>-macos-unsigned-preview.zip`，解压后打开 `DAViewer.app`。需要 macOS 12 或更高；当前是未签名、未公证的预览版，第一次打开需要右键选择「打开」。

一般用户请选择标记为 Latest 的版本，标记为 Pre-release 的是预览版。发布页同时提供 `SHA256SUMS` 用于校验文件；当前版本号和文件大小见[下载页](docs/download.md)。

## 首次使用

1. 下载并打开应用，首次启动会直接进入登录页。
2. 选择「登录或创建账号」，在内嵌的 DeviantArt 官方页面完成登录。登录方式由 DeviantArt 决定，DAViewer 不接触你的密码。
3. 回到首页就可以浏览、搜索、收藏和下载了。

个性化推荐等功能使用 DeviantArt 的网页会话，它和登录状态分开保存，也可能单独失效。如果登录后仍然提示登录，或推荐流加载不出来，按应用提示重新登录一次，或检查网络与代理。

更细的状态说明见[登录与会话](docs/authentication.md)。

## 常见问题

**登录成功了，为什么还提示登录？**

个性化推荐等功能用的是 DeviantArt 网页会话，它和登录状态分开保存，会单独过期。按提示在应用内重新登录一次即可。如果是网络被拦截，应用会说明是网络问题而不是未登录，这时换一个网络或代理节点、等一两分钟再刷新一次，比反复登录更有效。详见[登录与会话](docs/authentication.md)。

**推荐流或每日精选加载不出来怎么办？**

先确认网络和代理可用（「设置 → 网络代理」里有连通性测试），再下拉刷新一次。

**成人内容怎么显示？**

DAViewer 只能请求成人内容，是否显示由 DeviantArt 账号的浏览偏好决定。请在「设置 → DeviantArt 账号设置」里打开官方设置页，然后重新登录一次。

**为什么有些原图下载不了？**

付费、私密、仅订阅可见或受版权限制的作品不提供原图，应用会在作品页显示原因；原图不可用时的降级规则见[下载作品](#下载作品)。

**怎么设置代理？**

在「设置 → 网络代理」手动填写地址，格式为 `host:port` 或 `http://host:port`，端口填代理软件显示的 HTTP / Mixed 端口；没有手动设置时，应用会自动尝试系统代理和环境变量。应用只支持 HTTP CONNECT 类型，不支持 SOCKS5、带用户名密码的地址和 PAC，各平台登录用的 WebView 覆盖范围也不同，详见[网络与代理](docs/networking.md)。

**macOS 提示「无法验证开发者」怎么办？**

当前是未签名、未公证的预览版。请在 Finder 中右键选择「打开」，或到「系统设置 → 隐私与安全性」中允许运行。

**怎么反馈问题？**

「设置 → 诊断」会生成预填好的 GitHub Issue 链接，日志已去掉令牌、Cookie 等敏感字段，提交前可以自己检查。也可以直接到 [Issues](https://github.com/redtidev1918/DAViewer/issues) 提交；安全问题请走 [SECURITY.md](SECURITY.md)。

## 开发与贡献

DAViewer 是 Flutter 应用，可复用的部分沉淀在同作者的 SDK [DAKit](https://github.com/redtidev1918/DAKit) 中：DAKit 负责 OAuth、官方 API、网页兼容适配器和后台传输，DAViewer 负责界面、路由与平台集成。边界和取舍见[架构说明](docs/architecture.md)。

```shell
flutter pub get
flutter run -d macos        # 或 windows / Android 设备 ID
```

需要 Flutter 3.47.1（CI 固定的版本）。构建、发版和提交前检查的完整说明见[构建说明](docs/build.md)与 [CONTRIBUTING.md](CONTRIBUTING.md)。

<details>
<summary>构建命令与提交前检查</summary>

```shell
flutter build apk --release     # Android，需要 android/key.properties
flutter build macos --release
flutter build windows --release
```

Release 构建需要 `--dart-define=DAVIEWER_VERSION=<版本>`，否则应用无法正确提示更新。想用自己的 OAuth public client，加上 `--dart-define=DAKIT_CLIENT_ID=<你的_PUBLIC_CLIENT_ID>`，并在其白名单里加入 `dakit://oauth/callback`；普通用户不需要。

Dart 改动后请运行：

```shell
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

</details>

## 文档

这份 README 负责整体介绍和上手，登录状态、代理细节、架构边界、构建与发布流程都在[文档站](https://redtidev1918.github.io/DAViewer/)和 `docs/` 目录里。按任务选择：

| 你想做什么 | 文档 |
| --- | --- |
| 下载安装包 | [下载页](docs/download.md) |
| 解决登录、会话和常见问题 | [登录与会话](docs/authentication.md) |
| 配置网络和代理 | [网络与代理](docs/networking.md) |
| 了解应用与 SDK 的边界 | [架构说明](docs/architecture.md) |
| 本地构建、发版 | [构建说明](docs/build.md) |
| 核对发布前验证与剩余风险 | [发布门禁](docs/release-gate.md)、[回归目录](docs/regressions/README.md) |

Issue、PR 和文档改进都欢迎。安全问题请走 [SECURITY.md](SECURITY.md)。

## 项目说明

- DAViewer 是社区开发的第三方客户端，与 DeviantArt 没有隶属关系，也没有获得 DeviantArt 的授权或合作。DeviantArt 是其所有者的商标。
- 登录使用 DeviantArt 官方登录页，客户端不保存 `client_secret`，也不接触你的密码。
- 作品版权归各自的创作者所有。下载功能只是把你有权访问的公开文件保存到本地，请遵守 DeviantArt 的服务条款和作品的使用许可。
- 应用依赖 DeviantArt 的官方 API 和部分网页接口，这些接口随时可能变化，相关功能可能因此失效。
- 项目使用 [MIT 许可证](LICENSE)。

## 致谢

DAViewer 建立在 [DAKit](https://github.com/redtidev1918/DAKit) 与 [Flutter](https://flutter.dev) 之上；
WebView、状态管理、路由、图片缓存、视频播放与富文本分别由 `flutter_inappwebview`、`flutter_riverpod`、
`go_router`、`cached_network_image`、`chewie` / `video_player`、`flutter_html` 承担，完整清单见
[pubspec.yaml](pubspec.yaml)。网页私有接口的解析参考了 [gallery-dl](https://github.com/mikf/gallery-dl) 与
[deviantart.ts](https://www.npmjs.com/package/deviantart.ts)。

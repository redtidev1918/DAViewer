# DAViewer

<p align="center">
  <img src="assets/icon/icon.png" alt="DAViewer" width="128" />
</p>

**语言 / Language:** 中文 · [English](README.en.md)

DAViewer 是一个用 Flutter 写的开源 DeviantArt 第三方客户端，支持 Android、Windows 和 macOS。浏览、搜索、收藏、关注和下载，都在一个应用里完成。

DAViewer 不是 DeviantArt 官方应用，与 DeviantArt 没有隶属或合作关系。

[![GitHub license](https://img.shields.io/github/license/redtidev1918/DAViewer?style=flat)](LICENSE) [![GitHub release](https://img.shields.io/github/v/release/redtidev1918/DAViewer?style=flat)](https://github.com/redtidev1918/DAViewer/releases) [![Platforms](https://img.shields.io/badge/platform-Android%20%7C%20Windows%20%7C%20macOS-blue?style=flat)](#下载与安装) [![Docs](https://img.shields.io/badge/Docs-文档站点-6366f1?style=flat-square)](https://redtidev1918.github.io/DAViewer/)

**[下载最新版本](https://github.com/redtidev1918/DAViewer/releases)** · [文档站](https://redtidev1918.github.io/DAViewer/) · [首次使用](#首次使用) · [常见问题](#常见问题)

## 截图

<table align="center">
  <tr>
    <td align="center"><img src="docs/screenshots/home_feed.jpg" width="200" /><br /><sub>首页推荐</sub></td>
    <td align="center"><img src="docs/screenshots/artwork_detail.jpg" width="200" /><br /><sub>作品详情</sub></td>
    <td align="center"><img src="docs/screenshots/related_works.jpg" width="200" /><br /><sub>相关作品与原图下载</sub></td>
  </tr>
</table>

## 能做什么

### 浏览与发现

- **推荐**：根据你 DeviantArt 网页会话里的信息生成个性化推荐流。网页会话缺失或失效时会提示重新登录，不会用通用内容冒充推荐。
- **每日精选**：通过 DeviantArt 官方 API 获取的当日精选。
- **关注动态**：底部「关注动态」标签，集中查看你关注的画师的新作品，顶部可以切换画师。
- **搜索**：输入即出结果（约 0.45 秒防抖），可在作品和用户之间切换；输入 `#标签` 可直接进入标签页，作品结果还能切换默认 / 最新排序。
- **标签页**：浏览某个标签下的作品，可切换最新或热门。
- **打开链接**：首页右上角的链接按钮，粘贴 DeviantArt 作品或画师链接即可跳转。

搜索、标签、关注动态都需要登录后使用。

### 作品与画师

- **作品详情**：大图浏览、多图分页，双击可放大；左右滑动切换相邻作品，并提前加载下一张。
- **视频与动图**：视频自动播放、循环，可拖动进度、调节音量和播放速度，加载失败可重试；GIF 作品带角标。
- **作品信息**：标题、作者、描述、标签，以及原图的可用状态和文件大小；可一键分享。
- **画师主页**：资料、作品、收藏的作品、日志和自定义画集；画廊内可直接搜索。
- **更多类似作品**：在作品页继续发现相关作品，可随时刷新。
- **关注**：在画师主页关注或取消关注，并在关注列表里查看已关注的画师。

### 收藏与互动

- **收藏**：在作品详情页收藏或取消收藏，底部「收藏」标签浏览自己的收藏。
- **收藏集**：查看自己的收藏集及其中的作品。
- **通知**：官方消息列表，未读数量显示在首页铃铛上。已读状态保存在本机，因为 DeviantArt 没有提供公开的标记已读接口。
- **访问历史**：本机记录你最近打开过的作品，最多 200 条，从搜索页右上角的历史按钮进入，可一键清空。

### 下载与个性化

- **原图优先**：作品可下载时直接保存原图，并显示文件大小。多图作品可以一次下载全部页面。
- **受限时降级**：原图需要付费、受权限限制或已失效时，只有纯图片作品会降级保存当前展示的图片（这不是原图）；作品里只要有视频，就不会降级，视频海报也不会被当成视频文件下载。付费、私密和受版权限制的作品无法下载。
- **下载管理**：底部「下载」标签查看进度，传输中可暂停、继续、取消和重试；完成后可以打开文件，桌面端还能直接打开所在文件夹，Android 会保存到系统「下载」目录。也可以一键清理已完成的记录。
- **设置**：浅色 / 深色 / 跟随系统，中英文界面，清除缓存，检查更新，查看或导入导出 DeviantArt 账号 Cookie，以及登录与退出登录。
- **诊断**：生成一个预填好的 GitHub Issue 链接，诊断日志会先去掉访问令牌、Cookie 等敏感内容，提交前由你自己确认。

## 下载与安装

稳定版在 [Releases](https://github.com/redtidev1918/DAViewer/releases) 页面，按平台选择文件：

| 平台 | 文件名 | 安装 |
| --- | --- | --- |
| Android | `DAViewer-v<版本>.apk` | 打开 APK 安装 |
| Windows | `DAViewer-v<版本>-windows.zip` | 解压后运行 `daviewer.exe` |
| macOS | `DAViewer-v<版本>-macos-unsigned-preview.zip` | 解压后打开 `DAViewer.app` |

- **Android**：需要 Android 7.0 或更高。安装未知来源应用时系统会提示，按提示允许即可。
- **Windows**：解压后请保留同目录的所有文件，不要只把 `daviewer.exe` 单独移走，否则应用无法启动。
- **macOS**：需要 macOS 12 或更高。当前发布的是未签名、未公证的预览版，首次打开请在 Finder 中右键选择「打开」，或在「系统设置 → 隐私与安全性」里允许。应用会用系统钥匙串保存登录令牌，系统询问时选择「允许」。

发布页同时提供 `SHA256SUMS`，可用于校验下载的文件。如果某个版本被标记为 Pre-release，那是预览版；一般用户请选择标注为 Latest 的版本。当前版本号和文件大小也可以在[下载页](docs/download.md)查看。

## 首次使用

1. 下载并打开应用。
2. 首次启动会直接进入登录页。点「登录或创建账号」，在内嵌的 DeviantArt 官方页面完成登录。
3. 登录成功后回到首页的推荐流，就可以浏览、搜索、收藏和下载了。

登录方式由 DeviantArt 官方页面决定，DAViewer 只是把这个页面嵌入应用，不接触你的密码。

一次登录会同时建立两套会话，它们用途不同，也会分别失效：

- **OAuth 会话**：用于 DeviantArt 官方 API，包括每日精选、作品信息、收藏、关注、下载，以及搜索里的用户结果。令牌保存在系统钥匙串或凭据库中。
- **网页会话（Cookie）**：用于 DeviantArt 只在网页上提供的功能，包括个性化推荐流、画师画廊搜索和搜索里的作品结果（官方 API 作为备选）。保存在应用数据目录中。

也就是说，登录成功并不代表所有功能都可用：网页会话失效时，推荐流和画廊搜索会提示重新登录，而其他功能仍然正常。反过来，网页会话有效也不能替代 OAuth。

未登录时能做的事情很少：只有登录页、设置和访问历史可用，搜索、标签、收藏、下载、通知、画师主页和作品详情都会要求先登录。

退出登录（设置 → 退出登录）会清除 OAuth 令牌、浏览器 Cookie 和本地网页会话文件。

更细的状态说明见[登录与会话](docs/authentication.md)。

## 常见问题

**已经登录过了，为什么还提示登录？**

推荐流和画师画廊用的是网页会话，它和 OAuth 会话是两套东西，会单独过期。按提示重新在应用内登录一次即可。如果是因为网络被拦截、代理不可用，应用会给出网络或网络挑战的说明，而不是「未登录」，这时换一个网络或代理节点、等一两分钟再刷新一次，比反复重新登录更有效。

**推荐流或每日精选加载不出来怎么办？**

先确认网络和代理可用（设置 → 网络代理里有连通性测试），然后下拉刷新一次。推荐流在应用回到前台且超过 10 分钟后也会自动刷新。

**成人内容怎么看？**

DAViewer 只能向 DeviantArt 请求成人内容，是否显示由 DeviantArt 账号自己的浏览偏好决定。请在「设置 → DeviantArt 账号设置」打开官方页面的成人内容设置，并在应用中重新登录一次，让网页会话生效。部分年龄受限的多图作品官方 API 不提供，需要有效的网页会话才能解析。

**为什么有些原图下载不了？**

付费、私密、仅订阅可见或受版权限制的作品不提供原图，应用会显示对应原因。原图不可用时，只有纯图片作品会降级保存当前展示的图片，这不是原图；含视频的作品不会降级，视频海报也不会被当作视频下载。

**怎么设置代理？**

「设置 → 网络代理」可以手动填代理地址，格式是 `host:port` 或 `http://host:port`，端口填代理软件里显示的 HTTP / Mixed 端口。没有手动设置时，应用会依次尝试系统代理、环境变量（`https_proxy` / `http_proxy` / `all_proxy`）、构建时内置的代理，最后直连。

代理只支持 HTTP CONNECT 类型，不支持 SOCKS5、带用户名密码的代理地址和 PAC。各平台登录用的 WebView 覆盖范围也不同：Android 全局生效；Windows 通过 WebView2 参数生效；macOS 14 及以上支持，macOS 12 / 13 只能依赖系统代理。详见[网络与代理](docs/networking.md)。

**macOS 提示「无法验证开发者」怎么办？**

当前发布的是未签名、未公证的预览版。请在 Finder 中右键选择「打开」，或到「系统设置 → 隐私与安全性」中允许运行。

**「检查更新」会自动下载新版本吗？**

不会。应用会定时静默检查 GitHub 上的最新版本，发现新版本时显示提示；点提示只会在浏览器里打开 Releases 页面，由你自己选择是否下载。应用不会自动下载或安装更新。

**怎么反馈问题？**

「设置 → 诊断」可以生成一个预填好的 GitHub Issue 链接，日志会去掉令牌、Cookie 等敏感字段，提交前你可以自己检查内容。也可以直接到 [Issues](https://github.com/redtidev1918/DAViewer/issues) 提交。安全问题请走 [SECURITY.md](SECURITY.md)。

## 关于 DeviantArt

- DAViewer 是社区开发的第三方客户端，与 DeviantArt 没有隶属关系，也没有获得 DeviantArt 的授权或合作。DeviantArt 是其所有者的商标。
- 登录使用 DeviantArt 官方登录页，客户端不保存 `client_secret`，也不接触你的密码。
- 作品版权归各自的创作者所有。下载功能只是把你有权访问的公开文件保存到本地，请遵守 DeviantArt 的服务条款和作品的使用许可。
- 应用依赖 DeviantArt 的官方 API 和部分网页接口，这些接口随时可能变化，相关功能可能因此失效。

## 进阶与开发

### 本地运行

```shell
flutter pub get
flutter devices          # 查看设备 ID
flutter run -d macos
flutter run -d windows
flutter run -d <设备ID>   # Android
```

需要 Flutter 3.47.1（CI 固定的版本）和 Dart 3.13.1 及以上。依赖已发布的 DAKit 包，版本见 [pubspec.yaml](pubspec.yaml)。

### 应用结构

DAViewer 是 Flutter 应用，可复用的部分沉淀在同作者的 SDK [DAKit](https://github.com/redtidev1918/DAKit) 里：DAKit 负责 OAuth、官方 API、网页兼容适配器和后台传输，DAViewer 负责界面、路由和平台集成。边界和取舍见[架构说明](docs/architecture.md)。

### 构建

```shell
flutter build apk --release          # Android，需要 android/key.properties
flutter build macos --release        # macOS
flutter build windows --release      # Windows
```

Release 构建需要 `--dart-define=DAVIEWER_VERSION=<版本>`，否则应用无法正确提示更新。工具链、签名和 macOS 未公证预览版的说明见[构建说明](docs/build.md)。

### 发布

发布由 ReleaseGraph 和 release-please 驱动，配置见 [.release-policy.yml](.release-policy.yml)。每个版本的中文 Release 正文放在 `.github/release-notes/<版本>.md`；Actions 里的 **Release** 工作流可以手动验证或修复已有版本。发布前的人工验证记录见[发布门禁](docs/release-gate.md)和[回归目录](docs/regressions/README.md)。

### 自定义 OAuth 应用

普通用户不需要注册 OAuth 应用。要用自己的 public client，加上 `--dart-define=DAKIT_CLIENT_ID=你的_PUBLIC_CLIENT_ID`，并在应用白名单里加入 `dakit://oauth/callback`。

### 提交改动

Dart 改动后请运行：

```shell
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

## 文档

这份 README 负责整体介绍和上手；登录状态、代理细节、架构边界、构建与发布流程都在[文档站](https://redtidev1918.github.io/DAViewer/)和 `docs/` 目录里。按任务选择：

| 你想做什么 | 文档 |
| --- | --- |
| 下载安装包 | [下载页](docs/download.md) |
| 解决登录、会话和常见问题 | [登录与会话](docs/authentication.md) |
| 配置网络和代理 | [网络与代理](docs/networking.md) |
| 了解应用与 SDK 的边界 | [架构说明](docs/architecture.md) |
| 本地构建、发版 | [构建说明](docs/build.md) |
| 核对发布前验证与剩余风险 | [发布门禁](docs/release-gate.md)、[回归目录](docs/regressions/README.md) |

Issue、PR 和文档改进都欢迎，见 [CONTRIBUTING.md](CONTRIBUTING.md)；安全问题请走 [SECURITY.md](SECURITY.md)。

## 致谢

DAViewer 建立在 [DAKit](https://github.com/redtidev1918/DAKit) 与 [Flutter](https://flutter.dev) 之上；
WebView、状态管理、路由、图片缓存、视频播放与富文本分别由 `flutter_inappwebview`、`flutter_riverpod`、
`go_router`、`cached_network_image`、`chewie` / `video_player`、`flutter_html` 承担，完整清单见
[pubspec.yaml](pubspec.yaml)。网页私有接口的解析参考了 [gallery-dl](https://github.com/mikf/gallery-dl) 与
[deviantart.ts](https://www.npmjs.com/package/deviantart.ts)。

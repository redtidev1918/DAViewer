# DAViewer

<p align="center">
  <img src="assets/icon/icon.png" alt="DAViewer" width="160" />
</p>

**语言 / Language:** 中文 · [English](README.en.md)

> DeviantArt 官方已停止维护其移动客户端。DAViewer 是一个基于 [DAKit](https://github.com/redtidev1918/DAKit) 的开源 DeviantArt 客户端，面向 Android、macOS 与 Windows，以原生应用提供网页版的主要功能。

[![GitHub stars](https://img.shields.io/github/stars/redtidev1918/DAViewer?style=flat&color=yellow)](https://github.com/redtidev1918/DAViewer/stargazers) [![GitHub license](https://img.shields.io/github/license/redtidev1918/DAViewer?style=flat)](LICENSE) [![GitHub release](https://img.shields.io/github/v/release/redtidev1918/DAViewer?style=flat)](https://github.com/redtidev1918/DAViewer/releases) [![Platforms](https://img.shields.io/badge/platform-Android%20%7C%20macOS%20%7C%20Windows-blue?style=flat)](https://github.com/redtidev1918/DAViewer/releases) [![Flutter](https://img.shields.io/badge/Flutter-3.47.1-blue?style=flat&logo=flutter)](https://flutter.dev)
[![Docs](https://img.shields.io/badge/Docs-文档站点-6366f1?style=flat-square)](https://redtidev1918.github.io/DAViewer/)

## 安装

从 [Releases](https://github.com/redtidev1918/DAViewer/releases) 下载对应平台的安装包：

- **Android**：`DAViewer-v<版本>.apk`
- **macOS 12+ 测试版**：`DAViewer-v<版本>-macos-unsigned-preview.zip`（同时支持 Intel 与 Apple Silicon；解压后拖入「应用程序」）
- **Windows**：`DAViewer-v<版本>-windows.zip`（解压后运行 `DAViewer.exe`）

每个平台只发布**一个**资产，文件名固定为 `DAViewer-v<版本>-<平台>`；`v` 前缀是命名规范的一部分，
不是装饰。历史 Release 上可能残留旧协议的重复文件（例如同时存在 `DAViewer-0.2.184.apk` 与
`DAViewer-v0.2.184.apk`），这只是旧协议留下的遗留物，**不是**当前流水线的产物。

Windows 版解压即用：登录全程在 App 内完成，不会改动系统设置、不需要管理员权限，也不安装任何服务；文件夹移到任何位置都能直接运行。

> **关于 macOS 版本**：这是社区免费发布的测试版，没有走 Apple 的官方审核（那需要付费的开发者账号），所以首次打开时 macOS 会拦截一次。请在 Finder 中**右键点 App 图标，选择「打开」**，即可正常使用——App 不会上传或收集任何数据。

## 截图预览

<table align="center">
  <tr>
    <td align="center"><img src="docs/screenshots/home_feed.jpg" width="200" /><br /><sub>首页推荐</sub></td>
    <td align="center"><img src="docs/screenshots/artwork_detail.jpg" width="200" /><br /><sub>作品详情</sub></td>
    <td align="center"><img src="docs/screenshots/related_works.jpg" width="200" /><br /><sub>相关推荐</sub></td>
  </tr>
</table>

## 目录

- [为什么做这个项目](#为什么做这个项目)
- [功能特性](#功能特性)
- [与 DAKit 的关系](#与-dakit-的关系)
- [参考与致谢](#参考与致谢)
- [使用前准备](#使用前准备)
- [运行](#运行)
- [代理](#代理)
- [构建与发布](#构建与发布)
- [首页与登录态](#首页与登录态)
- [登录常见问题](#登录常见问题)
- [贡献](#贡献)
- [说明](#说明)

## 为什么做这个项目

- DeviantArt 官方已停止维护其客户端 App；
- 网页版功能丰富（推荐、画廊、标签、收藏、关注、下载），但缺少桌面/移动原生体验；
- 本项目把网页版的主要功能与原生交互结合起来，开箱即用，无需自己注册 OAuth 应用。

## 功能特性

- **登录**：一个「登录或注册」入口，在 App 内嵌网页中打开 DeviantArt 官方登录页，页面里可直接选择 DeviantArt、Google、Apple 或 Facebook；一次登录同时建立官方 OAuth 会话与网页会话（个性化推荐、收藏集）
- **个性化推荐**：首页「推荐」来自网页版 `rfy/deviations` 个性化推荐流（网页 Cookie + CSRF），与官网推荐一致
- **搜索**：实时搜索（边输边出结果）+ 历史记录（紧凑标签样式）+ 粘贴 DeviantArt 链接直达作品/作者；搜索页「为你推荐」与「热门标签」带作品预览图（Pixiv 风格）
- **作品详情**：左右滑动或顶部按钮切换前后作品（相邻作品图片预加载）；双指缩放；多图分页；标题下方显示发布时间与更新时间（相对时间，自动刷新）
- **媒体**：图片统一缩放；视频最高画质、自动播放并循环、可拖进度、失败重试；GIF 角标 + 富文本图片带缓存和加载进度
- **相关内容**：详情页原生展示「更多类似作品」、相似画师、已被收录 / 建议收藏集（点击可打开完整内容）、作者更多作品；空结果与失败有明确提示
- **标签**：详情/搜索/标签页统一标签条，缺失标签自动从官方数据补全；标签页支持「最新 / 热门」排序
- **作者**：资料（含简介、关注者数、加入时间）、画廊（可搜索作者自己的作品）、自定义分画廊（画集）、收藏夹、关注
- **分享**：作品、画师、画廊分组、收藏集和标签均可调用系统原生分享；作品仍可单独复制链接
- **社交**：收藏（含收藏态）、关注/取关作者、关注列表、通知（未读红点 + 本地已读）
- **下载**：实时确认原图权限；缩略图预览；不可下载时说明原因并降级保存最高画质预览；长按图片可单张下载（先确认再入队）；完成后提示实际保存位置；支持打开文件/文件夹与删除确认
- **外观与设置**：浅色 / 深色 / 跟随系统；语言与外观设置持久化；清除缓存；检查更新
- **更新提醒**：首页有新版本时显示可关闭的提示条，点击即可查看本次更新内容，再决定是否下载；被忽略的版本不再打扰，不弹窗、不自动下载
- **问题报告**：日志与诊断页一键生成预填好的 GitHub Issue（可选附带脱敏日志）；App 不收集、不上传任何数据
- **双语**：中文 / English 切换
- **网络**：自动检测系统代理、直连测试与可选手动代理；能直连的国际网络无需配置，受限网络按实际代理端口设置

## 与 DAKit 的关系

`DAViewer` 是应用，DAKit 是 SDK。客户端只依赖已发布的 DAKit 包，不复制 SDK 代码；OAuth、官方 API 映射、领域模型与后台传输归 DAKit，通用私有网页协议解析归可选的 `dakit_web`，WebView 会话、能力路由与原生交互归 DAViewer。依赖版本：

```yaml
dependencies:
  dakit_core: ^1.1.0
  dakit_api: ^1.0.0
  dakit_flutter: ^1.0.0
  dakit_web: ^0.2.1
```

每次登录只创建一个官方 OAuth/PKCE 事务，全部账号选择、密码和人机验证都留在 App 内嵌网页的官方页面中。回调后 App 同时使用这一份 OAuth 身份与网页会话，不再要求第二次网页登录。未登录是正常引导状态。详细边界见 [架构说明](docs/architecture.md)。

## 参考与致谢

DAViewer 建立在以下开源项目之上：

- **[DAKit](https://github.com/redtidev1918/DAKit)** —— 本项目的 DeviantArt SDK（OAuth、官方 API 映射、领域模型、后台传输），已发布到 pub.dev，文档见 [DAKit 文档](https://github.com/redtidev1918/DAKit#文档)
- **[Flutter](https://flutter.dev)** —— 跨平台 UI 框架
- **[flutter_inappwebview](https://pub.dev/packages/flutter_inappwebview)** —— 内嵌网页（登录、网页适配器）
- **[flutter_riverpod](https://pub.dev/packages/flutter_riverpod)** —— 状态管理
- **[go_router](https://pub.dev/packages/go_router)** —— 路由
- **[dio](https://pub.dev/packages/dio)** —— HTTP 客户端
- **[cached_network_image](https://pub.dev/packages/cached_network_image)** / **[flutter_cache_manager](https://pub.dev/packages/flutter_cache_manager)** —— 图片缓存
- **[flutter_secure_storage](https://pub.dev/packages/flutter_secure_storage)** —— 安全存储（登录令牌）
- **[share_plus](https://pub.dev/packages/share_plus)** —— 系统原生分享
- **[url_launcher](https://pub.dev/packages/url_launcher)** —— 打开外部链接
- **[path_provider](https://pub.dev/packages/path_provider)** —— 本地路径
- **[chewie](https://pub.dev/packages/chewie)** / **[video_player](https://pub.dev/packages/video_player)** —— 视频播放
- **[flutter_html](https://pub.dev/packages/flutter_html)** —— 富文本渲染

网页私有接口的逆向参考：

- **[gallery-dl](https://github.com/mikf/gallery-dl)** —— 记录了 DeviantArt 网站私有数据提取方式的下载器项目
- **[deviantart.ts](https://www.npmjs.com/package/deviantart.ts)** —— DeviantArt API 的 TypeScript 封装，用于核对接口参数

## 使用前准备

普通用户只需要一个 DeviantArt 账号，无需注册 OAuth 应用 —— 客户端内置了公开的 client id（Public OAuth client 没有 secret，client id 可以随应用分发）。

> 登录需要以下 OAuth 权限（应用启动时自动申请）：`basic`、`browse`、`collection`（收藏）、`user`（关注列表）、`user.manage`（关注/取消关注）、`gallery`、`feed`。

### 开发者：覆盖内置 client id

如果想用自己的 OAuth 应用（例如开发调试），通过 `--dart-define` 覆盖：

```shell
flutter run -d macos --dart-define=DAKIT_CLIENT_ID=你的_PUBLIC_CLIENT_ID
```

> 用自己的应用时，需在其白名单中精确加入 `dakit://oauth/callback`。

## 运行

```shell
flutter pub get
flutter run -d macos     # macOS
flutter run -d android   # Android
flutter run -d windows   # Windows
```

## 代理

应用运行时会按「App 手动设置 → 系统代理 → `https_proxy` / `http_proxy` / `all_proxy` → 构建参数」选择网络路径。「设置 → 网络代理」支持 `127.0.0.1:<你的代理端口>` 或 `http://127.0.0.1:<你的代理端口>`，设置会持久保存，并同时用于 API、图片、下载和后台公开网页适配器；页面内可直接测试 App 路径的 DeviantArt 连通性。登录在 App 内嵌网页中完成，遵循 App 的网络路径（手动代理同样生效）。

这里的端口没有固定值，必须以你的代理软件显示的 HTTP/Mixed 端口为准。在手机上，`127.0.0.1` 只表示代理也运行在同一部手机；如果代理运行在电脑或路由器，请填写它的局域网 IP，并开启“允许局域网”。App 会先测试直连：可用则不要求代理，不可用才给出代理排障，因此国际用户和受限网络用户不会被套用同一条提示。

从 Finder 直接启动通常不会继承终端的 `all_proxy`。macOS 12/13 的 App 内手动代理无法注入后台网页适配器，因此这两个版本请使用 macOS 系统代理。完整优先级、平台覆盖和排障方式见 [网络与代理说明](docs/networking.md)。

`flutter pub get` 与 Gradle 构建需要代理时的环境变量写法见 [构建说明](docs/build.md#proxying-builds)。

## 构建与发布

推送到 `main` 会触发 CI 的质量检查与 Android/macOS/Windows 构建；打 `v*` 标签会自动创建 GitHub Release 并上传构建产物（说明取自对应版本的 `RELEASE_NOTES.md` 用户文案）。

**一键发布（推荐）**：Actions → **Release** → Run workflow → 选 `patch` / `minor` / `major`（或填具体版本号）→ 运行。它会自动改版本号、提交、推 tag，随后 CI 构建并发布。

本地验证构建：

```shell
flutter build apk --release          # Android APK（需 android/key.properties）
flutter build macos --release        # macOS 应用
flutter build windows --release      # Windows 应用
```

签名、工具链版本（AGP / Gradle / Kotlin / flutter_inappwebview）与 macOS 未签名标记的细节见 [构建说明](docs/build.md)。

## 首页与登录态

首页是**原生界面**（推荐 / 每日精选 两个标签），底部另有「关注动态」一级标签（即 DeviantArt 的 `/watch/deviations`，关注画师的最新作品，顶部带按更新时间排序的头像排）。「推荐」来自网页版 `rfy/deviations` 个性化推荐流，使用网页 Cookie + CSRF，与官网推荐一致；「每日精选」使用官方 OAuth API。App 内嵌网页中的官方页负责账号、注册、社交提供商和安全验证；`dakit://oauth/callback` 在网页内被拦截并完成登录，没有第二份网页身份需要同步。

macOS 预览包使用稳定的项目签名，登录数据安全保存在系统钥匙串（密码保险箱）的独立 `DAViewer Account` 项目中；待处理的登录记录只是崩溃恢复数据，无法保存或清理时也不会阻断当前登录。

## 登录常见问题

- **DAViewer 没有自己的账号**：你登录的是 DeviantArt 官方账号，应用不额外注册账号、不保存密码。
- **忘记密码 / 注册账号**：点「登录或注册」后，统一由 DeviantArt 官方页提供。
- **Google / Apple / Facebook 登录**：在 App 内嵌网页里打开 DeviantArt 官方登录页，再选择页面当前提供的账号（Google、Apple 等入口都在页面上）。完成后自动回到 App，一次登录即可。
- **登录与代理**：登录在 App 内嵌网页中完成，遵循 App 的网络路径；手动填写的代理同样覆盖登录页。如果网页无法打开，可在登录前先运行连通性测试。
- **登录前检查代理**：原生登录入口会显示当前网络路径，可直接进入代理设置或运行连通性测试，不必等网页白屏后再排查。
- **出现人机验证**：这是官方页或账号提供商的安全流程，直接在内嵌网页里完成。App 不将 403/429/503 猜测成断网，也不干预它。
- **登录页没打开或卡住**：可点右上角「完成」关闭后重新打开；取消后才能开始一个全新登录事务，不会残留旧登录。
- **首次启动与离线恢复**：只要本机安全存储中存在有效的 OAuth 令牌，网络暂时不可用时也会保留登录态；从未登录的用户不会被误送进首页，老用户的登录不会因临时断网被误判为已登出。
- **成人内容**：DeviantArt 的账号浏览偏好优先于 App 请求。可在「设置 → DeviantArt 账号设置 → 成人内容设置」直达修改。
- **登录失败时仍可使用设置**：登录页右上角齿轮可进入语言、网络代理、日志与诊断、检查更新和关于；这些页面不受登录路由限制。
- **macOS 首次登录的安全确认**：macOS 自带一个「密码保险箱」（官方叫法：钥匙串）。把登录状态放进去之前，系统会先征求你的同意——这和正规软件保存你的密码时一样正常。看到「DAViewer Account 想要使用机密信息」时，选择「**允许**」或「**始终允许**」即可：这只是把登录信息安全地保存在本机，不会上传任何数据，也不会读取其他密码。如果系统因保险箱上锁而要求输入 Mac 密码，那只是 macOS 在解锁你自己的保险箱；App 不会收集或上传你的密码。

登录与会话恢复的完整状态规则见 [登录与会话说明](docs/authentication.md)。

## 贡献

欢迎任何形式的贡献 —— 提 Issue、修 Bug、加功能、完善文档都行。详见 [CONTRIBUTING.md](CONTRIBUTING.md)。安全漏洞请走 [SECURITY.md](SECURITY.md)，社区准则见 [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md)。

1. Fork 本仓库，从 `main` 开分支；
2. 改动后运行 `dart format lib test`、`flutter analyze` 和 `flutter test`；
3. 发 PR 描述清楚「改了什么、为什么」。

客户端依赖的 SDK 是 [DAKit](https://github.com/redtidev1918/DAKit)（已发布到 pub.dev），涉及 SDK 的改动请到那边提 PR，两边一起发布。

如果觉得这个项目有用，点个 Star 能让它被更多人看到。

## 说明

- `DAViewer` 是第三方客户端，与 DeviantArt 无隶属关系；
- 客户端不保存 `client_secret`；
- 所有账号授权都使用 App 内嵌网页中的 DeviantArt 官方页；App 不内置或读取账号密码表单。

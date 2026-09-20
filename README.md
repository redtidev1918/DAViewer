# DAViewer

<p align="center">
  <img src="assets/icon/icon.png" alt="DAViewer" width="160" />
</p>

**语言 / Language:** 中文 · [English](README.en.md)

DeviantArt 官方已经停止维护它的客户端 App。DAViewer 是一个基于 [DAKit](https://github.com/redtidev1918/DAKit) 的开源客户端，用原生界面提供网页版的主要功能，面向 Android、macOS 和 Windows，开箱即用，不需要自己注册 OAuth 应用。

[![GitHub license](https://img.shields.io/github/license/redtidev1918/DAViewer?style=flat)](LICENSE) [![GitHub release](https://img.shields.io/github/v/release/redtidev1918/DAViewer?style=flat)](https://github.com/redtidev1918/DAViewer/releases) [![Platforms](https://img.shields.io/badge/platform-Android%20%7C%20macOS%20%7C%20Windows-blue?style=flat)](https://github.com/redtidev1918/DAViewer/releases) [![Docs](https://img.shields.io/badge/Docs-文档站点-6366f1?style=flat-square)](https://redtidev1918.github.io/DAViewer/)

## 安装

在 [Releases](https://github.com/redtidev1918/DAViewer/releases) 里下载对应平台的包：

- **Android**：`DAViewer-v<版本>.apk`
- **Windows**：`DAViewer-v<版本>-windows.zip`，解压后运行 `DAViewer.exe`；不装服务、不改系统设置、不需要管理员权限
- **macOS 12+**：`DAViewer-v<版本>-macos-unsigned-preview.zip`，Intel 与 Apple Silicon 通用，解压后拖进「应用程序」

macOS 首次打开会被系统拦一次，因为这是社区免费发布的测试版，没有 Apple 的付费签名。在 Finder 里右键点 App 图标选「打开」就能正常使用，App 不会上传或收集任何数据。

## 截图

<table align="center">
  <tr>
    <td align="center"><img src="docs/screenshots/home_feed.jpg" width="200" /><br /><sub>首页推荐</sub></td>
    <td align="center"><img src="docs/screenshots/artwork_detail.jpg" width="200" /><br /><sub>作品详情</sub></td>
    <td align="center"><img src="docs/screenshots/related_works.jpg" width="200" /><br /><sub>相关推荐</sub></td>
  </tr>
</table>

## 功能

- **登录**：在内嵌网页中打开 DeviantArt 官方登录页，可选 DeviantArt / Google / Apple / Facebook，一次登录同时建立官方 OAuth 会话和网页会话
- **首页**：原生界面，「推荐」（网页个性化推荐流）与「每日精选」（官方 API）两个标签，底部另有「关注动态」标签
- **搜索**：边输边出结果，带历史记录；粘贴 DeviantArt 链接直达作品或作者；「为你推荐」和热门标签带预览图
- **作品详情**：左右滑动切换前后作品，相邻图片自动预加载；双指缩放、多图分页、相对时间显示发布与更新时间
- **访问历史**：本地记录最近浏览的作品，最多 200 条，可从搜索页右上角进入并一键清空，不上传任何数据
- **媒体**：图片统一缩放；视频最高画质、自动循环、可拖动进度、失败重试；GIF 角标，富文本图片带缓存
- **相关内容**：详情页展示更多类似作品、相似画师、收藏集和作者更多作品
- **作者**：资料、画廊（可搜索作者自己的作品）、自定义画集、收藏夹、关注
- **社交**：收藏（含收藏态）、关注/取关、关注列表、通知（未读红点 + 本地已读）
- **下载**：实时确认原图权限，受限时说明原因并降级保存最高画质预览；长按图片可单张下载，完成后提示保存位置，可打开文件或文件夹
- **分享**：作品、画师、画廊分组、收藏集和标签都可以调用系统原生分享
- **设置**：浅色 / 深色 / 跟随系统，中英双语，清除缓存，检查更新；新版本只显示可关闭的提示条，不弹窗、不自动下载
- **问题报告**：诊断页一键生成预填好的 GitHub Issue；App 不收集、不上传任何数据

## 与 DAKit 的关系

DAViewer 是应用，DAKit 是 SDK。OAuth、官方 API 映射、领域模型和后台传输归 DAKit，通用私有网页协议解析归可选的 `dakit_web`，WebView 会话与原生交互归 DAViewer；客户端只依赖已发布的包，不复制 SDK 代码，版本见 [pubspec.yaml](pubspec.yaml)。完整边界见 [架构说明](docs/architecture.md)。

## 运行

```shell
flutter pub get
flutter run -d macos     # macOS
flutter run -d android   # Android
flutter run -d windows   # Windows
```

普通用户只需要 DeviantArt 账号，不用注册 OAuth 应用——客户端内置的 client id 是公开的、不含 secret。开发时想用自己的 OAuth 应用，加参数 `--dart-define=DAKIT_CLIENT_ID=你的_PUBLIC_CLIENT_ID`，并在应用白名单里精确加入 `dakit://oauth/callback`。

## 代理

应用按「App 手动设置 → 系统代理 → `https_proxy` / `http_proxy` / `all_proxy` → 构建参数」选择网络路径，设置会持久保存，并同时用于 API、图片、下载和后台网页适配器。端口填代理软件显示的 HTTP/Mixed 端口，没有固定值；手机上 `127.0.0.1` 只在代理也运行在同一部手机时成立。App 会先测直连，能直连的用户不会被套用代理提示。完整规则见 [网络与代理](docs/networking.md)。

## 构建与发布

推送到 `main` 会跑 CI 质量检查，打 `v*` 标签会自动创建 Release（说明取自 `RELEASE_NOTES.md`）。发版走 Actions → **Release** → Run workflow，选 `patch` / `minor` / `major` 或填具体版本号。本地构建：

```shell
flutter build apk --release          # Android APK（需 android/key.properties）
flutter build macos --release        # macOS 应用
flutter build windows --release      # Windows 应用
```

签名、工具链版本和 macOS 未签名标记的细节见 [构建说明](docs/build.md)。

## 登录常见问题

- **账号**：你登录的是 DeviantArt 官方账号，应用不注册账号、不保存密码；忘记密码或注册账号都由官方页处理。
- **Google / Apple / Facebook 登录**：在 App 内嵌网页的官方登录页上选择，完成后自动回到 App，一次登录即可。
- **人机验证**：这是官方页或账号提供商的安全流程，直接在内嵌网页里完成，App 不干预。
- **登录页打不开或卡住**：点右上角「完成」关闭后重新打开；登录前也可以先跑一次连通性测试。
- **成人内容**：「设置 → DeviantArt 账号设置 → 成人内容设置」直达修改，账号的浏览偏好优先。
- **首次启动与离线**：本机安全存储里有有效令牌时，网络暂时不可用也会保留登录态；登录页打不开时，右上角齿轮里仍可进入语言、代理、诊断和检查更新。
- **macOS 首次登录的安全确认**：系统会先征求把登录状态保存到本机「密码保险箱」（钥匙串）的许可，和正规软件保存密码一样正常，选「允许」或「始终允许」即可，不会上传任何数据。如果系统要求输入 Mac 密码，那是在解锁你自己的钥匙串。

完整的状态规则见 [登录与会话说明](docs/authentication.md)。

## 贡献

Issue、Bug 修复、新功能和文档都欢迎，详见 [CONTRIBUTING.md](CONTRIBUTING.md)；安全问题请走 [SECURITY.md](SECURITY.md)，社区准则见 [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md)。

1. Fork 仓库，从 `main` 开分支；
2. 改动后运行 `dart format lib test`、`flutter analyze` 和 `flutter test`；
3. 发 PR 说清楚改了什么、为什么。

涉及 SDK 的改动请提到 [DAKit](https://github.com/redtidev1918/DAKit)，两边一起发布。觉得这个项目有用的话，点个 Star 能让更多人看到。

## 说明

- DAViewer 是第三方客户端，与 DeviantArt 无隶属关系；
- 客户端不保存 `client_secret`；
- 账号授权全部使用 App 内嵌网页里的 DeviantArt 官方页面，App 不内置也不读取账号密码表单；
- 私有网页接口的解析参考了 [gallery-dl](https://github.com/mikf/gallery-dl) 和 [deviantart.ts](https://www.npmjs.com/package/deviantart.ts)。

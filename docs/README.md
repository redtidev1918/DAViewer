# DAViewer 文档中心

**语言 / Language:** 中文 · [English](/en/)

项目文档索引。面向用户的介绍与安装说明见根目录
[README.md（中文）](https://github.com/redtidev1918/DAViewer/blob/main/README.md) 与
[README.en.md（English）](https://github.com/redtidev1918/DAViewer/blob/main/README.en.md)。

本站按账号统一文档规范组织：`docs/` 根为**中文**，`docs/en/` 为**英文**，
中英同名页一一对应（下表可直接对照）。

## 下载

Android / Windows / macOS 安装包见 [下载页](download.md)，始终指向最新 Release；
英文版见 [Download](/en/download.md)。

## 开发者文档

| 中文 | English |
| --- | --- |
| [架构说明](architecture.md)：SDK 与应用边界、作品数据流、相关内容状态、手势归属、认证、应用内状态与发布约定 | [Architecture](en/architecture.md) |
| [网页适配器 —— 兼容性契约](web_adapter.md)：逆向网页接口的兼容约定（端点注册表、回退策略与变更排查手册） | [Web adapter](en/web_adapter.md) |
| [认证与会话恢复](authentication.md)：单 OAuth 模型、冷启动恢复、macOS 钥匙串存储、Cookie 导入导出、成人内容 | [Authentication and session recovery](en/authentication.md) |
| [网络与代理](networking.md)：运行时优先级、各平台 WebView 覆盖、连通性测试与恢复 | [Networking and proxy](en/networking.md) |
| [构建说明](build.md)：固定工具链、Release/CI 约定、pub get 与 Gradle 构建的代理配置 | [Build notes](en/build.md) |

## 参与与合规

参与贡献见 [CONTRIBUTING.md](https://github.com/redtidev1918/DAViewer/blob/main/CONTRIBUTING.md)；
安全漏洞请走 [SECURITY.md](https://github.com/redtidev1918/DAViewer/blob/main/SECURITY.md)；
社区准则见 [CODE_OF_CONDUCT.md](https://github.com/redtidev1918/DAViewer/blob/main/CODE_OF_CONDUCT.md)。

## 相关

- [DAKit 文档](https://github.com/redtidev1918/DAKit/blob/main/docs/README.md)：本应用依赖的
  上游 SDK（OAuth、官方 API 映射、领域模型、后台传输）。SDK 相关问题请在那边提出。

## 约定

- `docs/` 根为中文，`docs/en/` 为英文，同名页一一对应；改动其中一页时请同步另一页。
- 文档只描述当前行为；历史决策见
  [CHANGELOG.md](https://github.com/redtidev1918/DAViewer/blob/main/CHANGELOG.md) 与
  [RELEASE_NOTES.md](https://github.com/redtidev1918/DAViewer/blob/main/RELEASE_NOTES.md)。

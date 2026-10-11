# DAViewer 文档

语言 / Language：中文 · [English](en/README.md)

DAViewer 是面向 Android、macOS 和 Windows 的 DeviantArt 第三方客户端。项目介绍和截图见 [README](https://github.com/redtidev1918/DAViewer/blob/main/README.md)。

## 安装与使用

| 任务 | 文档 |
| --- | --- |
| 下载对应平台的安装包 | [下载](download.md) |
| 登录、恢复会话、管理 Cookie、设置成人内容 | [认证与会话恢复](authentication.md) |
| 配置代理、检查连接、了解 WebView 限制 | [网络与代理](networking.md) |

## 开发与维护

| 任务 | 文档 | English |
| --- | --- | --- |
| 理解 SDK 与应用边界、数据流和手势 | [架构说明](architecture.md) | [Architecture](en/architecture.md) |
| 排查私有网页接口变更 | [网页适配器契约](web_adapter.md) | [Web adapter](en/web_adapter.md) |
| 配置工具链、本地构建和发布 | [构建说明](build.md) | [Build notes](en/build.md) |
| 核对发布条件和实机证据 | [发布门禁](release-gate.md) | 中文文档 |
| 查找历史缺陷、测试和未验证项 | [回归目录](regressions/README.md) | 英文索引，条目为中文或英文 |

贡献流程见 [CONTRIBUTING.md](https://github.com/redtidev1918/DAViewer/blob/main/CONTRIBUTING.md)，安全报告见 [SECURITY.md](https://github.com/redtidev1918/DAViewer/blob/main/SECURITY.md)，社区准则见 [CODE_OF_CONDUCT.md](https://github.com/redtidev1918/DAViewer/blob/main/CODE_OF_CONDUCT.md)。OAuth、官方 API 映射、领域模型和传输问题请查阅 [DAKit 文档](https://github.com/redtidev1918/DAKit/blob/main/docs/README.md)。

## 文档维护

用户说明与主要开发文档在 `docs/` 和 `docs/en/` 中成对维护。修改一页时同步对应语言；发布门禁、架构审计与回归记录保留各自原有语言。

当前行为以使用说明和架构说明为准。`architecture/` 中的审计与迁移记录、`regressions/` 中的缺陷记录用于追溯问题，阅读时注意其版本与验证范围。历史更新见 [CHANGELOG.md](https://github.com/redtidev1918/DAViewer/blob/main/CHANGELOG.md) 和 [RELEASE_NOTES.md](https://github.com/redtidev1918/DAViewer/blob/main/RELEASE_NOTES.md)。

下载页由 `.github/scripts/update_download_page.py` 生成。修改页面措辞时改生成脚本；中文预览片段在 `download-preview.md`。

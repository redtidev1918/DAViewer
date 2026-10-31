---
title: DAViewer 文档
description: DAViewer 帮助中心：安装、登录、网络代理、搜索收藏、下载与常见问题；以及面向开发者的架构与发布文档。
---

# DAViewer 文档

**语言 / Language:** 中文 · [English](en/README.md)

DAViewer 是面向 Android、macOS 和 Windows 的 DeviantArt 第三方客户端。项目介绍和截图见 [README](https://github.com/redtidev1918/DAViewer/blob/main/README.md)。

## 帮助中心

帮助你安装、使用 DAViewer，以及解决常见问题——按「我想做什么」查找：

| 我想…… | 页面 |
| --- | --- |
| 安装/更新应用 | [下载与安装](download.md) · [快速上手](help/getting-started.md) |
| 登录账号、处理登录失效 | [登录与账号](help/login-and-account.md) |
| 设置代理、解决连不上 | [网络与代理](help/network.md) |
| 搜索、收藏、浏览历史 | [浏览与搜索](help/browse-and-search.md) |
| 下载作品原图 | [下载与保存](help/download-artwork.md) |
| 隐藏 AI 作品、标签或画师 | [内容屏蔽](content-filtering.md) |
| 快速排查各种问题 | [常见问题](help/faq.md) |

## 开发者文档

架构、构建、测试与发布维护，面向贡献者与维护者：

| 任务 | 文档 | English |
| --- | --- | --- |
| 理解 SDK 与应用边界、数据流和手势 | [架构说明](architecture.md) | [Architecture](en/architecture.md) |
| 会话恢复与认证的实现契约 | [认证与会话恢复](authentication.md) | [Authentication](en/authentication.md) |
| 排查私有网页接口变更 | [网页适配器契约](web_adapter.md) | [Web adapter](en/web_adapter.md) |
| 代理机制与平台覆盖 | [网络与代理](networking.md) | [Networking internals](en/networking.md) |
| 配置工具链、本地构建和发布 | [构建说明](build.md) | [Build notes](en/build.md) |
| 核对发布条件和实机证据 | [发布门禁](release-gate.md) | [Release gate](en/release-gate.md) |
| 明确各层测试与验证要求 | [测试规范](TESTING.md) | [Testing](en/TESTING.md) |
| 查找历史缺陷、测试和未验证项 | [回归目录](regressions/README.md) | 英文索引，条目为中文或英文 |
| 阅读架构审计与迁移记录 | [架构审计记录](en/architecture/cookie-lifecycle.md)（共 4 篇，英文） | 同左 |

贡献流程见 [CONTRIBUTING.md](https://github.com/redtidev1918/DAViewer/blob/main/CONTRIBUTING.md)，安全报告见 [SECURITY.md](https://github.com/redtidev1918/DAViewer/blob/main/SECURITY.md)，社区准则见 [CODE_OF_CONDUCT.md](https://github.com/redtidev1918/DAViewer/blob/main/CODE_OF_CONDUCT.md)。OAuth、官方 API 映射、领域模型和传输问题请查阅 [DAKit 文档](https://github.com/redtidev1918/DAKit/blob/main/docs/README.md)。

## 文档维护

帮助中心与主要开发文档在 `docs/` 和 `docs/en/` 中成对维护。修改一页时同步对应语言；架构审计与回归记录保留各自原有语言；用户操作内容以帮助中心为唯一权威，工程页只保留实现契约并互相链接。历史更新见 [CHANGELOG.md](https://github.com/redtidev1918/DAViewer/blob/main/CHANGELOG.md) 和 [RELEASE_NOTES.md](https://github.com/redtidev1918/DAViewer/blob/main/RELEASE_NOTES.md)。

下载页由 `.github/scripts/update_download_page.py` 生成。修改页面措辞时改生成脚本；中文预览片段在 `download-preview.md`。

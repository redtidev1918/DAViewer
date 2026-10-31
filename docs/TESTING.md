---
title: 测试规范
description: DAViewer 测试策略：七个验证层次、L1 本地质量门命令、fixture 编写规则与证据状态词汇。
---

# 测试规范

语言 / Language：中文

本文是 DAViewer 测试策略的规范入口：定义验证层次、本地质量门、CI 检查与实机验收之间的关系。发布验收条件见 [发布门禁](release-gate.md)，历史缺陷与证据见 [回归目录](regressions/README.md)。**自动化测试通过不能替代实机验证。**

## 验证层次

| 层次 | 范围 | 执行方式 |
| --- | --- | --- |
| L1 本地质量门 | 每次 Dart 改动提交前 | 命令见下节，与 CI 一致 |
| L2 单元 / Widget 测试 | `test/`（`*_test.dart`） | `flutter test`；当前无 `integration_test/` |
| L3 CI 质量检查 | PR 与 `main` 推送 | `.github/workflows/ci.yml` |
| L4 SDK 联合验证 | 改动 `lib/**`、`test/**`、`pubspec.*`、构建脚本的 PR | `.github/workflows/sdk-integration.yml` |
| L5 三平台候选构建 | PR 与发布 | ReleaseGraph 质量矩阵；Windows/macOS 实际启动 Release 程序做冒烟 |
| L6 实机验收 | 发布候选 | 按 [发布门禁](release-gate.md) 人工执行并记录 |
| L7 回归证据 | 行为变更 | [回归目录](regressions/README.md) 新增或更新条目 |

## L1 本地质量门

```shell
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test --dart-define=DAVIEWER_VERSION=0.7.0
```

`DAVIEWER_VERSION` 取 `.release-please-manifest.json` 当前值（CI 同样从 manifest 注入）。省略它会让依赖版本号的更新检查测试失真；自动更新检查需要这个 define，不能省略。完整构建命令见 [构建与发布](build.md)。

## 测试编写规则

1. **协议 fixture 必须来自真实证据。** 消费外部 API、网页协议或第三方数据结构的解析逻辑，测试样本必须取自独立获取的真实抓取（记录抓取时间与来源），禁止从当前实现反推。这是 AGENTS.md 永久规则（源自 `@publicSession` 键名事故）。
2. **fixture 走生产写入路径。** 持久化与恢复类测试必须通过生产代码写入再读回。教训见 [REG-026](regressions/026-web-session-restore-decode.md)：store 测试用裸 JSON helper 绕过 `read()` 组合点，586 个绿灯测试没有发现恢复路径早已失效。
3. **Widget 测试清理定时器。** 被测对象含 Timer / periodic 回调时，在 `tearDown` 显式取消，避免 testWidgets 泄漏导致用例挂起。
4. **行为变更必须带回归测试。** 修缺陷先写出对旧代码失败的测试，再修复；证据边界（已知与未知）写进回归条目，沿用既有状态词汇。
5. **用户可见文案**进 `lib/core/l10n/app_strings.dart`，中英双语，配套更新 `app_strings_test.dart`。

## L3 CI 质量检查（ci.yml）

- `flutter analyze` 与 `dart format` 校验（CI 只检查不重写文件）。
- 带 manifest 版本 define 的 `flutter test`。
- 当前 manifest 版本的中文 release notes 检查，规则以 [构建与发布](build.md) 为准。
- 发布资产命名规范：`scripts/build-release` 与 `.release-policy.yml` 只允许 `DAViewer-v*` 形式的资产名。

## L4 SDK 联合验证（sdk-integration.yml）

对 `lib/**`、`test/**`、`pubspec.yaml`、`pubspec.lock`、`scripts/build-release` 等路径变更的 PR 自动运行：检出 DAKit 固定 SHA，先跑 DAKit workspace 校验，再把应用依赖切到该 SDK 源码跑全量 analyze/format/test，最后构建三平台候选包（Windows/macOS 候选实际启动）。

修改 DAKit 的流程约束：先在 DAKit 仓库修复并发布包版本，再更新本仓依赖与锁文件，重跑本层验证；正式构建拒绝携带候选 Git override。详见 [构建与发布](build.md) 的发布流程。

## L6 实机验收

按 [发布门禁](release-gate.md) 的路径表执行：登录与恢复、推荐流、网页会话、WebView、提示条、收藏通知、代理、内容与下载。依赖 WebView、Keychain、原生手势的改动必须附实机证据（[CONTRIBUTING](https://github.com/redtidev1918/DAViewer/blob/main/CONTRIBUTING.md) 要求）。当前仓库没有 `integration_test/` 目录；如未来引入，须同步更新本文、CI 与发布门禁。

## 证据状态词汇

回归与验收结论沿用仓库既有词汇，不引入第二套词表：

- 回归条目：`Verified` / `Partial` / `Unverified` / `Blocked by Environment`（定义见 [回归目录](regressions/README.md)）。
- 发布门禁：`Code Verified` / `CI Verified` / `Release Verified` / `Android Verified` / `Original Incident Verified`（出处：session-recovery 归档）。

测试通过最多支撑 `Code Verified`；`Android Verified` 与 `Original Incident Verified` 只能来自真实设备与保留账号证据。

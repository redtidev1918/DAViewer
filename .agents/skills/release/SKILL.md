---
name: release
description: DAViewer 版本发布操作流程——中文 release notes、release-please 版本 PR、ReleaseGraph 构建与发布后核验。当需要发布新版本、准备版本 PR、核对发布资产或更新下载页时使用。
---

# DAViewer 发布流程

依据 `docs/build.md`、`.release-policy.yml`、`release-please-config.json` 与历史发布记录编写，命令与门槛以这些来源为准。人工验收条件见 `docs/release-gate.md`；本文只讲操作顺序。

## 前提

- `main` 为绿（最新 CI 通过），待发布变更已合并。
- 待发布变更以 `feat:` / `fix:` 等约定式提交进入 `main`——release-please 只对这类提交生成版本 PR。纯 `docs:` / `chore:` 提交不触发版本变更，**不要为文档或工程治理变更强行发版**。
- DAKit 依赖为已发布版本：`flutter pub get` 正常解析，`pubspec.lock` 无 path override。

## 步骤

1. **先写中文 release notes（notes-first 顺序）。** 确认下一个版本号（看 release-please 已打开的 `chore(main): release X` PR 标题，或 CHANGELOG 待发布段），在 `.github/release-notes/X.md` 写正文：含「本次更新」小节、中文、面向最终用户、每条一句话、约 4 条，不写根因分析或内部组件名；文风细则见 `.github/release-notes/README.md`。notes PR 必须先于版本 PR 合并——v0.5.14 曾因版本 PR 分支早于 notes 合并导致 CI 失败被迫 rebase，v0.5.15 起验证了 notes-first 顺序。
2. **核对版本 PR。** release-please 的 `chore(main): release X` PR 应更新 `pubspec.yaml`、`.release-please-manifest.json`、`CHANGELOG.md`，且 `pubspec.yaml` 与 manifest 版本一致。若该 PR 分支早于 notes 合并（CI 报 missing Chinese release notes），把版本 PR 分支 rebase 到最新 `main` 后 force-push。等待 PR 检查全绿（Analyze and test、quality、branch-contract）。
3. **合并版本 PR**（仓库惯例 squash）。合并后 `main` 推送自动触发 `release.yml`（ReleaseGraph）；未自动运行或失败时，Actions → Release → Run workflow 手动触发，参数见 `docs/build.md`。
4. **核验发布运行**：
   - `gh run list --workflow=release.yml --limit 3` 确认运行成功；
   - `gh release view vX` 确认 tag、非 draft、资产齐全：`DAViewer-vX.apk`、`DAViewer-vX-windows.zip`、`DAViewer-vX-macos-unsigned-preview.zip`、`SHA256SUMS`、`RELEASE-METADATA.json`。
5. **核验下载页。** 发布成功后 `post_publish` 自动运行 `update-download-page.yml` 并部署 Pages；打开线上下载页确认「本页版本：vX」与三个资产链接均正确（以部署后的页面为准，不是仓库副本）。
6. **记录发布证据。** 按 `docs/release-gate.md`「候选版本记录」要求归档：版本、commit、DAKit 依赖版本、检查命令与结果、实机验证范围、未验证项及是否阻塞。证据结论写进对应回归记录或 `.agent/STATUS.md`，并区分 `Release Verified` 与 `Android Verified`——**发布成功不是实机证据**。

## 禁止事项

- 不跳过或强推未绿的门禁；`force` 参数仅用于重跑已健康版本，`dry_run` 用于只构建验证。
- 不为纯文档变更发布客户端版本。
- 不把发布成功写成实机验收完成。

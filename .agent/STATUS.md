# 工程状态

> 当前工程状态的摘要快照，每次重要任务结束或发布后更新。任务进度的权威是 [TASKS.md](TASKS.md)；CI、Release、PR 的平台事实以 GitHub 为准，本文件不复制它们。

- 更新时间：2026-10-31（文档站系统优化 PR #145）
- 当前版本：v0.7.0+239（2026-10-17 发布并核验，见 [CHANGELOG](../CHANGELOG.md)）
- 分支：`main` 与远端同步，无未合并功能改动。工作区存在本地未跟踪残留（`docs/agent-tasks/session-recovery/audits/` 部分备份、`.review-tmp/`、`.tmp-session-import/`、`.workbuddy/`、`clear/` 及两个 stash）——历史会话有意保留，不提交、不删除。
- 开发阶段：常规开发。2026-10-16 P0 会话恢复任务关闭后曾宣布维护模式，实际自 v0.5.23 起恢复功能开发（v0.6.0 登录状态分通道、v0.7.0 本地内容过滤）。
- 依赖：DAKit 已发布版本 `dakit_api 1.2.0` / `dakit_core 2.0.0` / `dakit_web 0.3.0` / `dakit_flutter 1.1.0`；SDK 联合验证固定 SHA `f489f52`（`.github/workflows/sdk-integration.yml`）。

## 开放事项

- `Android Verified`（v0.5.22+ 实机回归）与 `Original Incident Verified` 仍为 PENDING：缺真实保留账号设备证据，见 `docs/agent-tasks/session-recovery/STATUS.md` 顶部。取得设备证据时优先补这两个结论。
- 回归目录中 `Partial` 条目与「Evidence still required」清单待补证据（`docs/regressions/README.md`）。

## 当前无阻塞

VitePress 迁移（T-005）已完成并上线。当前进行文档站系统优化（T-006，PR #145）：导航补全、英文补全、docsify 残留清理、逐页 frontmatter SEO；本地验证全绿（build 零死链、docsite check 9/9、navcheck 零警告）。客户端源码和 Flutter 依赖未改，不发布客户端版本；待 PR CI 与合并后 Pages 验收。

## 更新纪律

- 只记录可核实的事实并注明来源；不把计划写成已完成，不把测试通过写成实机验证。
- 发布后按 `.agents/skills/release/SKILL.md` 第 6 步回填本文件。
- 与 [HANDOFF.md](HANDOFF.md) 分工：本文件管跨会话状态，HANDOFF 管单次会话交接。

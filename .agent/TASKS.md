# 任务队列

> 任务进度的唯一权威，会话结束时更新。状态：`TODO / IN_PROGRESS / BLOCKED / DONE / DEFERRED`。用户可见的功能与缺陷跟踪以 GitHub issues 为准，本表只跟踪 Agent 工程任务；两个体系各自独立，不互相复制条目。

| Id | 任务 | 状态 | 说明 / 入口 |
| --- | --- | --- | --- |
| T-001 | Agent 工程治理体系落地 | DONE | PR #142 已合并（main `ea7a2fe`，squash）；PR CI 全绿，main 上 Release 运行成功且 build/finalize 跳过（release-please 正确忽略纯 `docs:` 提交），Pages 已部署。 |
| T-002 | Android Verified 实机证据（v0.5.22+） | BLOCKED | 缺真实保留账号设备；解锁条件：用户提供设备日志。按 `docs/agent-tasks/session-recovery/STATUS.md` 顶部要求补验。 |
| T-003 | Original Incident Verified 证据 | BLOCKED | 原始故障链的保留账号复验；解锁条件同 T-002。 |
| T-004 | 回归目录 Partial 项补证据 | DEFERRED | R1 / R3 / R7 / R17 / R22 / R23 及 `docs/regressions/README.md` 的设备证据清单；随相关功能开发顺带补，不单独立项。 |
| T-005 | VitePress 文档站迁移试点 | DONE | 迁移经 `3b202a5` 合并，PR #144（`8d8cb60`）修复截图布局，Pages 已上线；纯 `docs:` 提交未触发客户端发布。 |
| T-006 | 文档站系统优化 | DONE | PR #145 已合并（main `00eed67`，merge commit）；CI 全绿（docs/Analyze and test/branch-contract，release 正确 skipping），Pages 部署成功（run 41201701264），实站验收通过：新侧边栏分组、`/en/` 直达 200、新译页 200、meta description 上线、旧 vendor 404。 |
| T-007 | 认证文档恢复事务节精简 | DONE | PR #146 已合并；zh/en 两侧精简为现行摘要（保留实机验收警示、保守判证规则、诊断导出、状态映射，细节指向 REG-021 与归档），Pages run 41202427693 部署，实站标题已更新。 |
| T-008 | 文档站信息架构重构（帮助中心/开发者文档） | DONE | PR #147 已合并：docs/help 与 docs/en/help 各 6 个帮助页（以 app_strings 真实 UI 文案为写作依据），authentication/networking 用户内容迁出（单一权威），侧边栏双区、首页「我想……」任务表，现有路径零变动；download 页真实 v0.7.0 JSON 重放同步。CI 全绿（release 正确 skipping），Pages run 41204239255 部署，实站验收：12 个 /help/ 页 200、旧页 200、首页双区与下载页新链接在线。 |

## 更新规则

- 新任务先入表再动手；`BLOCKED` 必须写原因与解锁条件。
- `DONE` 需要证据（PR、release、测试日志链接）；证据不足只能保持 `IN_PROGRESS`。
- 已归档的大任务不回填本表（完整历史在 `docs/agent-tasks/`）。

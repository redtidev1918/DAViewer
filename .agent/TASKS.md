# 任务队列

> 任务进度的唯一权威，会话结束时更新。状态：`TODO / IN_PROGRESS / BLOCKED / DONE / DEFERRED`。用户可见的功能与缺陷跟踪以 GitHub issues 为准，本表只跟踪 Agent 工程任务；两个体系各自独立，不互相复制条目。

| Id | 任务 | 状态 | 说明 / 入口 |
| --- | --- | --- | --- |
| T-001 | Agent 工程治理体系落地 | IN_PROGRESS | PR #142：`.agent/`、`docs/TESTING.md`、`.agents/skills/*`、AGENTS.md 改写；合并后置 DONE。 |
| T-002 | Android Verified 实机证据（v0.5.22+） | BLOCKED | 缺真实保留账号设备；解锁条件：用户提供设备日志。按 `docs/agent-tasks/session-recovery/STATUS.md` 顶部要求补验。 |
| T-003 | Original Incident Verified 证据 | BLOCKED | 原始故障链的保留账号复验；解锁条件同 T-002。 |
| T-004 | 回归目录 Partial 项补证据 | DEFERRED | R1 / R3 / R7 / R17 / R22 / R23 及 `docs/regressions/README.md` 的设备证据清单；随相关功能开发顺带补，不单独立项。 |

## 更新规则

- 新任务先入表再动手；`BLOCKED` 必须写原因与解锁条件。
- `DONE` 需要证据（PR、release、测试日志链接）；证据不足只能保持 `IN_PROGRESS`。
- 已归档的大任务不回填本表（完整历史在 `docs/agent-tasks/`）。

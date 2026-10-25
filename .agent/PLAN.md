# 当前阶段计划

> 本阶段的目标、步骤与验收门槛。完成或方向变化时更新；功能开发计划以 GitHub issues / PR 为准，不在此复制。

## 阶段：Agent 工程体系落地（2026-10-26）

**目标**：任何新的 Coding Agent 只靠仓库文档即可理解约束、发现当前任务、延续工作并复用历史经验，不依赖上一段聊天上下文。

**步骤**：

1. [x] 审计既有体系（AGENTS.md、docs/、CI、release-please、回归目录、session-recovery 归档）。
2. [x] 建立 `.agent/`（STATUS / PLAN / TASKS / HANDOFF / DECISIONS / LESSONS）。
3. [x] 建立 `docs/TESTING.md`（复用既有门禁词汇，不开第二套标准）。
4. [x] 建立 `.agents/skills/release` 与 `.agents/skills/diagnosis`。
5. [x] 改写 AGENTS.md 为唯一 Agent 入口（保留两条永久规则与归档纪律）。
6. [x] 以独立 docs PR 合并（PR #142 → main `ea7a2fe`；PR 与 main CI 全绿，release-please 未产生版本 PR，Pages 已部署）。

**验收门槛**：

- 新增/修改文档的内部相对链接全部有效；各主题只有一个权威文件。
- PR 检查全绿；release-please 对纯 `docs:` 提交不产生版本 PR。
- 新 Agent 按 AGENTS.md 阅读顺序可定位当前任务、规则与测试门禁。

## 已完成的历史阶段

- P0 Android 会话恢复（runtime-stability Phase 1，v0.5.22 发布并核验）：已关闭并归档于 `docs/agent-tasks/session-recovery/`，勿重启（遗留验证项见 [TASKS.md](TASKS.md) T-002/T-003）。

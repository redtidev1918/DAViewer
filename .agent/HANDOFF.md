# 会话交接

> 每次 Coding Agent 会话结束时在顶部追加一节，只记本会话发生的事实与下一步入口。跨会话状态在 [STATUS.md](STATUS.md)，任务在 [TASKS.md](TASKS.md)。

## 条目模板

```
### <日期> <分支 / PR>
- 本会话改动：
- 验证情况（含未跑的检查）：
- 未提交内容与风险：
- 下一步入口：
```

### 2026-10-26 分支 docs/agent-governance

- 本会话改动：建立 `.agent/` 六件（STATUS/PLAN/TASKS/HANDOFF/DECISIONS/LESSONS）、`docs/TESTING.md`、`.agents/skills/release/SKILL.md`、`.agents/skills/diagnosis/SKILL.md`；改写 `AGENTS.md` 为唯一入口；`docs/_sidebar.md`、`docs/en/_sidebar.md`、`docs/README.md` 增加测试规范入口。
- 验证情况：新文档内部相对链接逐一核对指向真实文件；未跑 Flutter 测试（无代码改动，CI 在 PR 上全量执行）。
- 未提交内容与风险：工作区既有未跟踪残留（session-recovery audits 备份、`.review-tmp/`、`.tmp-session-import/`、`.workbuddy/`、`clear/`）与两个 stash 保持原样未动。注意 `stash@{1}`（backup-local-edits-before-update-2026-10-12）是明确禁止应用的旧备份。
- 下一步入口：PR 合并后置 T-001 为 DONE；后续功能开发走 GitHub issues，发布按 `.agents/skills/release/SKILL.md`。

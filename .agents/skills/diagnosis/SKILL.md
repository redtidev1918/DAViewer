---
name: diagnosis
description: DAViewer 登录、网页会话、网络代理与 DAKit 协议故障的诊断入口。当出现登录失败、推荐流为空、会话被误判、代理不通或私有协议解析错误时使用。
---

# DAViewer 故障诊断

流程：先按凭据通道分流，再取证，最后修复。禁止用「清数据 / 强制重登 / 加超时重试」代替诊断（session-recovery SPEC 的既定边界）。

## 第一步：按凭据通道分流

判别方法来自 v0.5.19 事故（session-recovery 归档 2026-10-14 条目）：看日志里失败请求走哪条通道。

| 现象 | 通道 | 入口文档 |
| --- | --- | --- |
| Bearer/OAuth 路径返回 200，Cookie+CSRF 路径 403 或失败 | 网页会话问题（OAuth 正常，不是登出） | `docs/authentication.md` |
| 两条通道都失败、连接拒绝或超时 | 网络或代理 | `docs/networking.md` |
| 请求成功但字段解析错误或缺失 | DAKit 私有协议适配器 | `docs/web_adapter.md`（端点注册表） |
| 官方 API 字段映射错误 | DAKit（上游修复后发版再更新依赖） | DAKit 仓库 |

## 第二步：取证

- 导出日志：Settings → Diagnostics（含最近 20 次启动）。
- 网页会话关键日志行（`[web-session]` 前缀）：`restore candidate` / `restore verified` / `restore skipped reason=...`；cookie `names=[...]`（只记名字，永远不记值）；verifier `classification=`（`signedIn` / `anonymous` / `page_uninitialized` / `blocked` / `challenge`）；`[home] rfy` 的 `accepted` / `transport_failed`；`genericFallback` / `personalization`。
- 每个结论标注证据等级；取不到证据时如实记 `Unverified`，不推测补全。日志原文不提交进仓库。

## 判读规则（已确认教训，防止误诊）

1. `rfy/deviations` 返回 HTTP 200 不证明网页会话健康——匿名 Cookie 也能拿到通用内容（REG-009 / 回归目录 R18）。会话结论只能由验证层提交。
2. 裸 HTTP 证据与已确认的浏览器身份冲突时，用真实 WebView 仲裁（`docs/release-gate.md`、`docs/authentication.md`）。
3. 单一匿名探针样本不能判定用户登出；匿名佐证需要更新的导航序号（REG-024）。
4. 网络传输失败 ≠ 用户登出：不清 OAuth、不清 Cookie（REG-025）。
5. OAuth 与网页会话是两条独立通道，状态可能不同步（v0.6.0 起设置页有分通道验证历史）；不要用一条通道的状态推断另一条。
6. 迟到的异步响应不得覆盖新账号状态（REG-019 请求所有权；epoch / credentials_changed 防线）。

## 环境备忘（Windows 主力机）

- `git push` 在系统 credential helper（GCM GUI 提示）下会挂起：改用 `git -c credential.helper= -c credential.helper='!gh auth git-credential' push`。
- Git Bash 下调 Flutter/Dart 注意 `dart.bat` / `flutter.bat` 解析；需要时给 PATH 加前缀 `/c/Windows/System32:/c/Windows:/c/Program Files/Git/cmd:/d/flutter-sdk/bin`。
- Dart VM 报 CreateFile 231（无法派生子进程）时先怀疑宿主沙箱限制，不是机器故障。

## 升级路径

- 代码级根因确认后写回归记录（`docs/regressions/`，沿用编号递增），注明证据边界。
- 会话恢复类历史故障先查 `docs/agent-tasks/session-recovery/`（已归档收尾，勿重启已收尾工作）。
- 协议解析问题在 DAKit `dakit_web` 修；修复前必须先取得真实抓取样本（AGENTS.md 永久规则）。
- 长期有效的结论沉淀到 `.agent/LESSONS.md`，详细经过留在归档。

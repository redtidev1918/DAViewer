# 故障教训

> 已确认故障的根因与防复发规则，每条带证据来源。详细经过在回归记录与归档，不在此复制；新教训在重大问题解决后追加，沿用编号。

## L-01 未验证的协议假设能穿透整条绿色流水线（v0.5.14 P0）

**发生了什么**：DeviantArt 渲染会话的键是 `@@publicSession`（双 `@`），实现、测试与多次重构都读单 `@` 键；登录成功但首页信息流永不加载。实现、测试、重构共用同一个未验证假设，数百个绿灯测试无法发现最基础的兼容性断裂。
**防复发**：D-0001 永久规则（真实证据先行）；fixture 从真实抓取构建并记录来源。
**来源**：`AGENTS.md` 永久规则、session-recovery 归档 2026-10-13 条目。

## L-02 测试绕过生产组合点 = 关键路径裸奔（REG-026）

**发生了什么**：`WebSessionStore.read()` 已把 cookies 解码为对象，三个消费方又按 JSON 重新解析，恢复路径静默失效约一个月（v0.5.14–v0.5.20）；store 自己的测试用裸 JSON helper 绕过 `read()`，586 个绿灯测试从未覆盖该组合点。
**防复发**：fixture 走生产写入/读取路径（`docs/TESTING.md` 规则 2）；为「组合点」本身写测试，不只测单元内部。
**来源**：`docs/regressions/026-web-session-restore-decode.md`、归档 2026-10-15 条目。

## L-03 HTTP 200 ≠ 网页会话健康（REG-009 / R18）

匿名 Cookie 也能让 `rfy/deviations` 返回 HTTP 200 通用内容；任何裸 HTTP 状态都不能单独得出会话结论，只有验证层能提交会话判定。
**来源**：`docs/regressions/009-rfy-200-generic-content.md`、回归目录 R18。

## L-04 弱证据不能下强结论：单匿名样本登出（REG-024）

滚动期间媒体 403、超时重试等高频触发面把请求带进探针，单个匿名探针样本就完成了一次权威登出判定。修复要求匿名佐证绑定更新的导航序号。评审标准：边界测试专项存在之前，弱证据永远不能证明安全。
**来源**：`docs/regressions/024-runtime-session-misjudge.md`。

## L-05 网络故障 ≠ 用户登出（REG-025）

连接拒绝与超时会触发浏览器探针和二次 RFY 传输，被当成会话问题处理。传输失败必须与身份证据分离；不清 OAuth、不清 Cookie。
**来源**：`docs/regressions/025-network-failure-auth-retry.md`。

## L-06 迟到的异步响应不得覆盖新账号状态（REG-019）

第一页请求有唯一所有权：恢复事务与显式重试是同一事务，用户手势总是重新拉取；同上下文重复刷新是 no-op，凭据轮换才重新请求（`credentials_changed` / epoch 防线）。
**来源**：`docs/regressions/019-first-page-request-ownership.md`。

## L-07 release notes 必须先于版本 PR 合并（v0.5.14）

版本 PR 分支早于中文 notes 合并时，CI 的 notes 检查失败，而 release-please 不会为文档提交刷新分支，只能手工 rebase + force-push。v0.5.15 起固定 notes-first 顺序。
**防复发**：`.agents/skills/release/SKILL.md` 步骤 1。
**来源**：归档 2026-10-13/0.5.15 条目。

## L-08 推送前本地跑格式检查（d0b284c）

`@@publicSession` 修复的首次推送只因 `dart format`（3 个文件）在 CI 失败。推送前本地执行 `dart format --output=none --set-exit-if-changed lib test`。
**来源**：归档 2026-10-13 条目、`docs/build.md`。

## L-09 发布成功不是实机证据

发布、资产校验、下载页核验都只支撑 `Release Verified`；`Android Verified` 与 `Original Incident Verified` 只能来自真实设备与保留账号证据。PENDING 必须如实保留，不因发布而关闭。
**来源**：session-recovery 归档（多处 gate status）、`docs/release-gate.md`、`docs/TESTING.md` 证据词汇节。

## L-10 OAuth 与网页会话是两条通道，混淆导致误诊

OAuth/Bearer 路径与 Cookie+CSRF 网页路径健康状态独立（v0.5.19：官方路径全 200、网页路径全 403）；曾把网页 403 误报为 `officialError`（归档 2026-10-14 修复）。诊断先分通道，UI 分通道提示（v0.6.0）与两套验证历史即源于此。
**来源**：`.agents/skills/diagnosis/SKILL.md` 判读规则、`docs/authentication.md`。

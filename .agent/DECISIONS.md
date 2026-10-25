# 技术决策记录

> 长期有效的架构与工程决策。一条决策一个事实，简短、带来源；详细论证在来源文档，不在此复制。状态：`Accepted` / `Superseded by D-XXXX`。

## D-0001 外部协议解析必须基于真实证据（2026-10-13，Accepted）

任何消费外部 API、网页协议、配置格式或第三方数据结构的解析逻辑，必须先对照独立获取的真实证据（实况抓取、留存文档或权威规范）验证数据结构；测试 fixture 从真实证据构建，禁止从当前实现反推，并记录样本来源与时间。导火索：`@publicSession` vs `@@publicSession` 键名事故（v0.5.14 登录成功但首页永不加载）。规则全文见 `AGENTS.md`；教训详见 [LESSONS.md](LESSONS.md) L-01。

## D-0002 DAKit 与 DAViewer 职责边界（Accepted）

DAKit 负责 OAuth、官方 API 传输与 DTO 映射、领域模型、凭据存储与通用私有协议解析（`dakit_web`）；DAViewer 负责 WebView 会话采集/刷新/持久化、能力路由、导航手势、UI 与宿主缓存。SDK 侧问题先在 DAKit 修复并发布，再更新本仓依赖。来源：`docs/architecture.md`、`CONTRIBUTING.md`。

## D-0003 网页响应一律映射为 DAKit 领域模型（Accepted）

业务层不维护第二套作品模型；HTML/JSON 解析集中在 `dakit_web`，不回业务代码；应用侧产品级 wrapper 限于 `lib/core/data/`。加绕行方案前先确认是否官方响应被映射错。来源：`docs/architecture.md`、`docs/web_adapter.md`。

## D-0004 发布链：release-please + ReleaseGraph，notes-first（Accepted）

版本管理用 release-please（跳过其 GitHub Release，由 `release.yml` 调 ReleaseGraph 构建发布）；资产名固定 `DAViewer-v*` 三平台 + SHA256SUMS + RELEASE-METADATA；中文 release notes 在版本 PR 之前合并。来源：`docs/build.md`、`.release-policy.yml`、`release-please-config.json`、`.agents/skills/release/SKILL.md`；教训 L-07。

## D-0005 会话结论只能由验证层提交（Accepted）

`rfy/deviations` HTTP 200 不证明网页会话健康（匿名 Cookie 也返回通用内容）；裸 HTTP 与已确认浏览器身份冲突时用真实 WebView 仲裁；单一匿名样本不能登出；网络传输失败不清除 OAuth。来源：`docs/release-gate.md`、`docs/authentication.md`、回归 R18 / REG-024 / REG-025；教训 L-03–L-05。

## D-0006 统一证据词汇，不开第二套标准（2026-10-26 随 TESTING.md 固化，Accepted）

回归条目用 `Verified / Partial / Unverified / Blocked by Environment`；发布门禁用 `Code Verified / CI Verified / Release Verified / Android Verified / Original Incident Verified`。来源：`docs/regressions/README.md`、session-recovery 归档、`docs/TESTING.md`。

## D-0007 双语文档成对维护，工程记录保留原语言（Accepted）

用户说明与主要开发文档在 `docs/` 与 `docs/en/` 成对维护；发布门禁、架构审计、回归记录保留各自原有语言（不强制翻译）。来源：`docs/README.md` 文档维护一节。

## D-0008 `.agent/` 工程体系与权威划分（2026-10-26，Accepted）

任务进度权威是 `.agent/TASKS.md`，工程状态摘要是 `.agent/STATUS.md`，单会话交接是 `.agent/HANDOFF.md`；GitHub issues 管用户可见跟踪，CI/Release 事实以平台为准；历史任务完整档案在 `docs/agent-tasks/`，`.agent/` 只引用不复制。来源：`AGENTS.md` 文档权威表。

## D-0009 纯文档变更不触发客户端发版（2026-10-26，Accepted）

`docs:` / `chore:` 提交不产生 release-please 版本 PR；工程治理与文档 PR 合并即完成，不发布新客户端版本。依据：release-please 约定式提交语义；`.agents/skills/release/SKILL.md` 前提节。

## D-0010 维护模式已被实际开发取代（记录性，2026-10-26）

2026-10-15 用户指令的 ≥60 天维护冻结（session-recovery 归档顶部）已被其后实际发布超越：v0.5.23–v0.7.0 于 2026-10-16/17 连续发布功能与修复。归档中的冻结指令保持原文作历史，当前以 [STATUS.md](STATUS.md) 为准。

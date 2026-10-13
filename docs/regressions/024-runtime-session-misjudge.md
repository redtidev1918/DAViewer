# REG-024: 运行期会话误判与分页跳登录（v0.5.17 后续）

日期：2026-10-14。分支：`codex/runtime-session-stability`（基线 main `5257454`，
v0.5.17）。任务书：`docs/agent-tasks/session-recovery/RUNTIME-STABILITY-SPEC.md`。
完整因果路径审计：`docs/agent-tasks/session-recovery/audits/runtime-session-causal-paths.md`。

## 现象

1. 自动登录恢复成功、推荐正常加载后，偶发"个性化推荐可能未加载"类警告。
2. 推荐信息流分页过程中偶发登录恢复 UI（信息流被登录组件替换 / 全局底部通知）。

用户提供的 2026-10-13 23:44–23:46 日志是**成功对照**（稳定 epoch/generation、
119 项分页、刷新正常），不是失败证据。设备上的具体失败样本**未捕获**。

## 根因（代码级 CONFIRMED；设备触发样本 UNVERIFIED）

### RC1 → 现象 1：group-2 游标弱证据独立触发用户可见降级

`rfyCursorSignalsGenericFallback` 把 `vespa_content_group==2` 当降级信号 →
`PersonalizedSessionPhase.degraded` → `RecommendedDegradedBanner` +
`recheckAfterWebSignal('rfy-generic-fallback')` 强制复核。REG-022 与 2026-10-13
生产日志均证明服务端确认已登录的会话同样收到 group-2（协议语义 UNVERIFIED）。
弱协议证据独立造成误报。

### RC2 → 现象 2：单次 anonymous 页面样本即权威登出 + 高频误触发面

`realBrowserProbe` anonymous 是权威登出（保留），但探测**一次**采样到
`username=='anonymous'` / `isLoggedIn==false`（重定向中间态、匿名壳、挑战变体
都可能呈现）立即完成 anonymous。触发强制复核的入口在滚动场景高频可达：
任意 401/403 文本的正则匹配（媒体栈）、rfy 自身 403（Dio 拦截器）、超时重试路径
`check(force:true, browser:true)`。bareProbe 在 WAF 下返回 unavailable 也一律
升级到该探测。

### RC3：自家探测导航轮换 Cookie → 在途分页被 `credentials_changed` 整页废弃

同代际（无登录/登出/锁死转换）的 Cookie 轮换使在途 rfy 结果整页废弃
（底部重试），属自伤。

### RC4：本地空 Cookie 与瞬时读取失败不可区分（边缘路径）

`WebSession.cookies()` 吞掉平台读取异常返回空列表；claimed-signed-in 场景下
曾可能直写 anonymous（绕过判决引擎的 `_setEmptyLiveCookieState` 分支）。

## 修复

两个并行会话的修改在同分支合并，互相补充：

| 修复 | 文件 | 内容 |
|---|---|---|
| F1 | `web_session_refresher.dart` | 探测 anonymous 佐证：首个 anonymous 样本只武装一次 reload 复核（`webSessionProbeSampleDecision` 纯函数），reload 后的样本才决定；confirmed 仍立即完成；期限内无佐证 → unavailable（绝不登出）。真实登出（Cookie 已死）第二次采样仍 anonymous，权威性保留 |
| F2 | `media_session_signal.dart` | 媒体信号主机归因：仅 deviantart.com 站点主机的 401/403 进入复核链；wixmp/CDN 与无法归因的错误文本不再触发全局复核；状态码正则收紧为需关键字前缀 |
| F3 | `home_providers.dart` | group-2 游标不再置 degraded / 不再强制复核 / 不落个性化缓存；仅记录 `personalization=unknown` 诊断；横幅不再由弱证据触发 |
| F4 | `web_session_status.dart` + `web_session_verdict.dart` | 空 Cookie + claimed-signed-in → unavailable（非 anonymous）；`localState/anonymous` 在 claimed 会话下 → unavailable；bareProbe 答案在凭据轮换后作废（credentials_superseded）；瞬态证据不推翻未过期 healthy 租约 |
| F5 | `personalized_request_policy.dart` | 同代际凭据轮换采纳在途结果（generation/账号/epoch/健康守卫全部保留） |
| UI | `home_screen.dart` | `rfy.session.unverified` 错误态不再展示登录动作（仅权威 `web.session.unavailable` 展示） |
| 诊断 | `web_session_status.dart` | `check(source:)` 记录 triggerSource/credentialRevision/eventId；废弃记录 decisionReason |

不变量对照：弱证据不登出（F1/F2/F4）↔1；真实失效仍生效（F1 保留权威 anonymous、
佐证后完成）↔2；分页失败保留内容（控制器原有 + F5 消除自伤废弃）↔3；身份转换
仅经判决链（未新增旁路）↔4；generation/epoch 守卫保留 ↔5；unknown 阶段允许
不确定 ↔6；有效账号不再被弱信号反复要求登录（F2/F3 收敛触发面）↔7。

## 测试

- `web_session_refresher_probe_test.dart`：anonymous 佐证决策序列（首样本武装、
  复核后决定、confirmed 立即完成、重定向中间态不能单样本登出）。
- `media_session_signal_test.dart`：主机归因（DA 站点转发、wixmp/deviantart.net
  CDN 不转发、无 URL 不转发）；widget 级转发/抑制用例改用可归因错误。
- `personalized_request_policy_test.dart` / `home_refresh_no_probe_test.dart`：
  同代际轮换采纳（RC3）、trace 元数据、跨账号/代际拒绝保留。
- `web_session_status_test.dart` / `web_session_verdict_policy_test.dart`：
  空本地 Cookie 不推翻 claimed 会话、凭据轮换作废旧复核答案、租约保留。
- 全量：`dart format --set-exit-if-changed` 0 changed；`flutter analyze` 无问题；
  `flutter test --dart-define=DAVIEWER_VERSION=0.5.17` **522 PASS**。

## 验收状态

```text
Code Verified: PASS（本地全量回归）
CI Verified: PENDING（PR 检查）
Release Verified: PENDING
Android Verified: PENDING（无真机/模拟器运行）
Original Incident Verified: PENDING（需要保留账号真机证据）
```

UNVERIFIED 保留：设备上 RC2 误判的具体页面形态（重定向中间态 vs 匿名壳 vs
挑战变体）——修复是结构性的（任何单样本形态都不再直接登出），但无失败时日志
佐证；group-2 协议语义。诊断日志（triggerSource/decisionReason/采样事件）已
可在下次发生时直接回答因果链。

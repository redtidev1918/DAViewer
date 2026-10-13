# 运行期会话误判 / 分页跳登录 —— 因果路径审计（Phase 1）

日期：2026-10-14。基线：main `5257454`（v0.5.17）。
任务书：`docs/agent-tasks/session-recovery/RUNTIME-STABILITY-SPEC.md`。
本文回答一个问题：**已经 healthy 的 Web 会话，在运行期（分页/刷新/详情/前后台切换）
还有哪些代码路径能把它变成 `needsLogin`，以及推荐页何时出现用户可见的降级警告。**

## 1. 登录 UI 的三种表现（D 链路，全部枚举）

| 表现 | 位置 | 触发条件 |
|---|---|---|
| U1 信息流被登录恢复组件替换 | `lib/features/home/home_screen.dart:241` | `webSessionStatusProvider.needsLogin == true`（任意时刻，已加载内容被整体遮盖，不丢数据） |
| U2 全局底部通知（含登录按钮） | `lib/shared/widgets/app_notice_host.dart:94` | 同上，任意路由可见，按 `web-session-<state>` id 可关闭 |
| U3 空列表错误态含登录动作 | `home_screen.dart:277-307` | `feed.error` 为 `web.session.unavailable` / `rfy.session.unverified` 且列表为空 |

**不存在自动路由跳转**：`router.dart` 的 redirect 只依赖 OAuth `authControllerProvider`
与 `webSessionReadyProvider`（启动恢复完成标志），从不读取 web 会话健康状态。
用户看到"跳登录"= U1 和/或 U2；点按钮才是 actual_navigation。

## 2. `needsLogin` 的全部判定生产者（A 链路）

`needsLogin = anonymous | stale | locked`（`web_session_status.dart:53`）。

- `locked`：仅 `markLocked()`，登录 WebView 中的 WAF 锁定页。运行期不会自发出现。
- `stale`：**无任何生产者**（死枚举值；`needsLogin` 包含它但无人写入）。
- `anonymous`，五条路径：
  - **A1** `localState/anonymous`（`web_session_status.dart:363-387`）：本地声称
    `isLoggedIn != true` / 用户名为空 / Cookie Header 为空。运行期有
    `shouldPreserveSignedInSessionOnAnonymousProbe` 保护，风险低。
  - **A2** `_setEmptyLiveCookieState(persistedCount: 0)` → `_setAnonymous('cookie-store')`
    （`web_session_status.dart:504`）：**直接写状态，绕过判决引擎**。关键缺陷：
    `WebSession.cookies()`（`web_session.dart:163`）把 CookieManager 平台异常吞掉并
    返回 `[]`——"暂时读不到"与"真的没有"不可区分。
  - **A3** `bareProbe/confirmed` 但用户名与声称不匹配 → anonymous。
  - **A4** `realBrowserProbe/anonymous` → **权威登出**（`web_session_verdict.dart:137`）。
    探测只要**一次**采样到页面明确呈现 `username=='anonymous'` 或 `isLoggedIn==false`
    （含 `getHtml()` 兜底解析）立即完成并返回 anonymous。
  - **A5** `realBrowserProbe/confirmed` 但用户名不匹配 → anonymous。

## 3. 运行期强制复核的全部触发源（每条都是 A4 的机会）

- **T1** Dio 拦截器（`web_session_coordinator.dart:123`）：www.deviantart.com 上
  非 `/`、非 `/oauth` 的 401/403、`/users/login` 重定向、`mature_loggedout`。
  **rfy 端点本身**（`/_puppy/dabrowse/networkbar/rfy/deviations`，dakit_web 0.3.0）
  走同一 Dio —— 分页自身 403 会触发强制复核。
- **T2** 周期定时器 60s（healthy 租约 5 分钟 → 实际约每 5 分钟一次真实校验）。
- **T3** App 恢复前台 → 强制。
- **T4** `MediaSessionSignal.report`（`media_session_signal.dart:36`）：
  `isAuthRejection` 用 `\b(401|403)\b` 匹配**任意错误文本**，不区分主机。
  调用点：feed 网格缩略图（`artwork_card.dart:119`）、详情页、媒体查看器、全屏查看器。
  wixmp CDN 签名 URL 过期 / 付费模糊预览的 403 在长滚动中**高频出现**。
- **T5** group-2 游标批次被接受后 `recheckAfterWebSignal('rfy-generic-fallback')`
  （`home_providers.dart:345`）。
- **T6** rfy 传输失败后的重试路径 `check(force: true, browser: true)`
  （`home_providers.dart:230`）——**直接运行真实浏览器探测**。
- **T7** 用户重试/下拉刷新时状态非 healthy → 强制。

升级链：bareProbe anonymous/**unavailable**（WAF 页、HTML 变化都会 unavailable）
且本地声称已登录 → 一律升级真实浏览器探测。即 T4/T1 的每次误触发都能到达 A4。

## 4. 分页与后台复核的竞争（B/C 链路）

- 探测（headless 导航首页）会让 DA 轮换 Cookie；在途 rfy 分页结果在
  `personalizedResultDiscardReason`（`personalized_request_policy.dart:19`）中因
  `!sameCredentials && sameGeneration → 'credentials_changed'` 被**整页废弃**
  （底部重试，内容保留）——我们自己发起的探测伤害了自己的在途请求。
- `_performCheck` healthy→`ensurePersistentSnapshot` 持久化浏览器 Cookie，同源无害。
- 请求门禁（`home_providers.dart:161-192`）：非 needsLogin 时先
  `check(force: cookieChanged(header))`；租约过期后分页请求会内联触发整条校验链。
- `webSession.cookies()` 瞬时失败 → 空头 → `cookieChanged('')==true` → 强制校验
  → 空头进 `_tryFetchRfy` → null → T6 强制浏览器探测。连锁浪费但可自愈。

## 5. 现象归因

**现象 1（偶发"个性化推荐可能未加载"警告）**
RC1（CONFIRMED，代码+REG-022+生产日志）：`rfyCursorSignalsGenericFallback` 把
`vespa_content_group==2` 游标当降级证据 → `PersonalizedSessionPhase.degraded` →
`RecommendedDegradedBanner`。group-2 语义 UNVERIFIED（REG-022：服务端确认已登录的
会话同样收到 group-2；2026-10-13 23:44 日志 `degraded -> usable` 证明生产中发生）。
弱协议证据独立造成用户可见误报 —— 违反验收目标 7。

**现象 2（分页中突然出现登录 UI）**
RC2（结构性 CONFIRMED；设备上的具体触发样本 UNVERIFIED）：滚动中
T4（缩略图 403 正则误报）/T1（rfy 或详情 API 403）/T6（超时）触发强制复核 →
bareProbe 被 WAF 挡成 unavailable → 升级 headless 探测 → **单次** anonymous 样本
（重定向中间态渲染 `isLoggedIn:false`、匿名壳页、挑战页变体）立即完成探测 →
A4 权威 anonymous → U1 整页替换 + U2 全局通知。
RC3（CONFIRMED by code）：探测导航轮换 Cookie → 在途分页 `credentials_changed`
废弃（次要可见伤害：底部重试）。
RC4（CONFIRMED by code，边缘）：`cookies()` 吞异常 + 持久层同时读空 → A2 直写
anonymous（不变量 1 违反路径）。

**真实性边界（不变量 2）**：Cookie 真死时 bareProbe→browserProbe 判 anonymous 是
正确行为，必须保留；修复不得以"永远 healthy"掩盖。

## 6. 修复设计（按根因范围）

| 修复 | 目标 | 机制 |
|---|---|---|
| F1 | A4 弱证据 | 探测判决加入佐证：首次 explicit_anonymous 只登记候选，静置后 **reload 复核**，第二次 anonymous 才完成；confirmed 仍立即完成；期限内未佐证 → unavailable（绝不登出） |
| F2 | T4 误报 | 媒体信号仅上报 deviantart.com 主机的 401/403（类型化 URI 或错误文本中的 URL 主机）；wixmp/CDN 与无法归因的文本不再触发全局复核 |
| F3 | RC1 | group-2 游标不再独立置 `degraded`：记录 `unknown`（允许不确定），不显示横幅；trace/不落缓存/`rfy-generic-fallback` 复核保留（真失效仍被捕获） |
| F4 | RC4/A2 | `_performCheck` 用 `readData()`（null=存储不可读）区分"读失败"与"真空"，读失败 → unavailable，不再进入 anonymous 分支 |
| F5 | RC3 | 判定链已保证 healthy+同账号+同代际+同请求时，同代际 Cookie 轮换（服务端/自家探测引起）不再废弃在途结果；跨代际保守规则不变 |

不变量对照：F1/F2/F4↔不变量1；F1 保留权威 anonymous↔2；控制器已保内容↔3；
F3/F5 不改变"仅判决链可写身份"↔4；generation/epoch 守卫未动↔5；
`unknown` 阶段与通知清退逻辑↔6；T4/T5 触发面收敛↔7。

## 7. UNVERIFIED 清单

- 设备上 A4 误判的具体页面形态（重定向中间态 vs 匿名壳 vs 挑战变体）——无失败时
  日志，只能靠 F1 的结构性修复 + 诊断日志在下次发生时留证。
- group-2 的真实协议语义（保持 UNVERIFIED，只移除其用户可见后果）。
- `stale` 枚举无生产者（历史遗留，未删）。

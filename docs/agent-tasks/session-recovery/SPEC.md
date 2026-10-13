# DAViewer — Android 推荐页会话恢复架构重构与生产故障根治

## 2026-10-13 当前优先事项补充：推荐分页缓存竞态

v0.5.16 真机新报告：缓存首屏先显示，过早滑动触底消耗分页触发锁；
网络首屏取得有效 Cursor 后仍不再加载。精确发布提交上的失败回归已确认
该宿主竞态，另已复现 Android 惯性滚动被过滤。最小修复和证据见
`docs/regressions/023-cached-feed-pagination-lock.md`；交付以 STATUS.md 最新检查点为准。

本轮不重构 OAuth、Web Session、DAKit 或整个 Feed。分页由服务端分页信息
和不透明 Cursor 驱动，不根据作品数量、固定页数或算法分组推测结束。
重复/循环 Cursor 是可恢复异常，不能伪装成正常末页。缓存、首屏刷新、
分页必须隔离；保留请求所有权、账号隔离、去重、取消和超时保护。

验收覆盖缓存 24 项提前触底后取得网络 Cursor、惯性滚动、连续至少三页、
失败重试及全宽底部状态。自动化和三平台构建不等于真实 Android 滚动验收。
原手机发布门禁已经由用户移除；CI/产物检查通过可合并发布，但 Android
及 Original Incident Verified 没有真实证据时必须保持 PENDING。
原任务书以下正文保留，不得据此重新开始已完成的架构工作。

## 0. 角色与任务

你是一名负责 Flutter / Android WebView / Riverpod / 并发状态管理的高级工程师。

你正在接管 DAViewer 的一个持续存在的 P0 生产故障。

仓库：https://github.com/redtidev1918/DAViewer

项目：基于 Flutter 的第三方 DeviantArt 客户端。

问题涉及：

- OAuth 与 Web Cookie 双重登录状态
- Flutter InAppWebView / HeadlessInAppWebView
- DeviantArt 页面初始化及 WAF 挑战
- Riverpod Provider 生命周期
- 个性化推荐接口 `rfy/deviations`
- 冷启动恢复、请求去重、缓存和并发竞争

**本任务要求实际调查、设计、修改、测试、提交和推进发布，而不是只提供建议或设计文档。**

目标是通过一次系统性架构修正，解决应用自身导致的会话恢复失败和重复推荐请求问题，而不是继续叠加固定超时、重复登录和更多重试次数。

注意：第三方网站的 WAF、认证协议和页面结构可能变化，因此不能承诺所有外部挑战都能无交互通过。我们要保证应用的恢复机制正确、可解释、可恢复，并且不因为自身架构缺陷反复要求登录。

---

## 1. 项目基线与历史背景

### 已发布版本

此前正式版本：`v0.5.13`

Release：
https://github.com/redtidev1918/DAViewer/releases/tag/v0.5.13

对应提交：`b88c374`

历史修复：

- PR #92：Headless WebView、推荐请求去重、缓存。
- PR #94：中文发布说明。
- PR #95：缓存单元测试及验收报告。

此前自动化验证：

- `flutter analyze` 通过。
- `flutter test` 419 passed。
- GitHub Actions 正式构建成功。
- Android APK 已正式发布。

但上述自动化验证**没有覆盖 Android 真机的原始故障条件**。

**2026-10-12 的真实 Android 测试表明 v0.5.13 依然存在故障，原始问题没有得到解决。**

开始执行时先检查 GitHub 最新 `main`、最新 Tag、PR 和工作区状态。若已有后续修复，必须分析实际差异，不要重复工作。

不要覆盖未提交修改，不要修改历史 Tag，不要直接在 main 上进行未经验证的实验。

---

## 2. 已确认的 Android 生产故障

2026-10-12 08:07，用户使用 v0.5.13，手机配置了有效代理：

```text
08:07:10 proxy = 127.0.0.1:7892
08:07:12 connectivity check = 200

08:07:12 OAuth token refreshed
08:07:12 persisted session restored
08:07:13 user/whoami = 200

08:07:12 personalized provider created id=1
08:07:12 personalized feed fetch request=rfy-1

08:07:12 Cookie count = 10
08:07:14 HTTP verifier classification=anonymous

08:07:18 web session:
unknown -> unverified
source=realBrowserProbe

08:07:23 HTTP verifier classification=anonymous
08:07:24 unverified -> unverified

08:07:28 HTTP verifier classification=anonymous
08:07:30 unverified -> unverified

08:07:46 用户手动打开登录 WebView

08:07:49 login WebView load stop
无 CSRF

08:07:53 首页 load stop
仍无 CSRF

08:07:54 首页再次完成导航
csrf=67
isLoggedIn=true

08:07:54 web session:
unverified -> healthy
source=web-login

08:07:54 fetch request=rfy-4

08:07:56 rfy-4 transport success
items=24
genericFallback=false
但没有对应 accepted 日志

08:07:58 fetch request=rfy-5

08:07:59 rfy-5 transport success
items=24
genericFallback=false

08:07:59 rfy-5 accepted
08:07:59 personalized feed cache saved
```

### 生产事实

1. OAuth 正常。
2. 网络与代理正常。
3. 本地 WebView Cookie 存在。
4. 后台自动验证无法确认有效 Web 会话。
5. 手动打开登录页面后，不需要重新输入账号密码，就能经过后续导航恢复有效会话。
6. 恢复后至少发生两次实际 RFY 首页网络传输。
7. 此次只有 Provider id=1，没有证据表明再次出现 Provider 重建。
8. `rfy-4` 返回了有效数据却未被接受，具体废弃原因尚不明确。

### 必须区分事实与假设

- Cookie 存在不证明 Cookie 仍有效。
- OAuth 有效不证明 Web 会话有效。
- HTTP `classification=anonymous` 可能是有效匿名，也可能是页面解析、页面状态或验证证据不充分造成的错误分类，需要检查。
- 手动登录页成功不必然证明 Headless WebView 只存在一种缺陷。
- `rfy-4` 和 `rfy-5` 可能涉及请求竞争、用户意图、Cookie 轮换或旧结果废弃，不能直接断言是 Provider 重建。

必须通过日志、源码和可复现测试确定因果关系。

---

## 3. 已发现的架构疑点

请优先检查以下文件：

```text
lib/core/auth/web_session_refresher.dart
lib/core/auth/web_session_verifier.dart
lib/core/auth/web_session_verdict.dart
lib/core/auth/web_session_status.dart
lib/core/auth/web_session_controller.dart
lib/core/auth/web_session_coordinator.dart
lib/core/auth/web_session_platform.dart

lib/core/data/web_session.dart

lib/features/web_login/web_login_screen.dart
lib/features/splash/splash_screen.dart

lib/features/home/home_providers.dart
lib/features/home/home_screen.dart

lib/core/feed/artwork_feed_controller.dart
lib/core/feed/artwork_feed_cache.dart
```

### 疑点 A：两套不同的身份确认逻辑

当前 Headless WebView 主要检查：

```dart
window.__INITIAL_STATE__['@@publicSession']
```

并尝试获取：

```dart
session.user.username
```

而可见登录 WebView 使用 `userinfo` Cookie、CSRF、已登录首页导航等信息进行确认。

两条路径的证据来源和成功判据不同。

**必须统一身份判定策略，但绝不能简单将 Cookie 存在视为服务端认证成功。**

### 疑点 B：CSRF 存在但用户名缺失时可能提前结束

当前 Headless 探测逻辑存在：

```dart
if (!observation.hasSessionMarkers &&
    _inconclusiveStops < _maxInconclusiveStops) {
  return;
}
await _dispose(result, completion);
```

其中：

```dart
hasSessionMarkers =
    pageUsername != null || csrf.isNotEmpty;
```

因此只要 CSRF 存在，就可能停止等待，即使身份仍然没有确认。

需要验证这条路径是否造成实际故障。

### 疑点 C：将 onLoadStop 误当作页面稳定信号

`onLoadStop` 不等于 JavaScript 已完成初始化，也不能保证后续 SPA 导航会再次触发。

当前最多三次采样和 20 秒超时只能限制等待，不能保证正确获取登录状态。

不应通过简单增加次数修补。

### 疑点 D：HTTP 匿名判定可能过度简化

检查 `WebSessionVerifier.usernameFromInitialState()`。

必须区分：

- 页面明确声明匿名。
- 页面结构缺失。
- 页面数据尚未生成。
- 解析失败。
- WAF 中间页面。
- 服务端不可用。

**页面解析不到用户名，不等于服务器确认用户已退出。**

### 疑点 E：多个组件同时参与会话恢复

目前启动、会话检查、浏览器探测、恢复监听、手动刷新和 FeedController 都可能触发关联操作。

应调查会话状态与推荐请求之间是否存在多个请求发起者，以及 generation、revision 和 Cookie 指纹变化引起的竞争。

### 疑点 F：诊断信息不足

部分 Headless 探测日志使用 `debugPrint`，用户提供的 AppLogger 文件无法还原探测内部过程。

必须让正式版能够导出足够的脱敏证据，准确说明每一次探测为何结束、每一次 RFY 结果为何被接受或废弃。

---

## 4. 目标架构：统一会话恢复协调器

设计以下逻辑边界，允许复用和改造现有类，不要求机械地新建所有文件。

```text
                  Application
                       |
                       v
             WebSessionOrchestrator
                       |
        +--------------+--------------+
        |              |              |
        v              v              v
 BrowserSessionHost  SessionEvidence  SessionRepository
                     Observer
        |              |              |
        +--------------+--------------+
                       |
                       v
              SessionDecisionEngine
                       |
                       v
             Verified Session State
                       |
                       v
           PersonalizedFeedCoordinator
                       |
           +-----------+-----------+
           |                       |
           v                       v
       RFY Transport          Feed Cache
           |                       |
           +-----------+-----------+
                       |
                       v
                    Feed UI
```

### 职责 1：WebSessionOrchestrator

它应该成为**唯一的 Web 会话恢复事务协调器**。

负责：

- App 冷启动后的恢复流程。
- 协调 Cookie 恢复。
- 启动浏览器会话观察。
- 归并重复验证请求。
- 管理超时及恢复策略。
- 管理 accountEpoch / recoveryId。
- 处理真实登录、退出及账号切换。
- 在验证成功后通知 FeedCoordinator。

不应由多个 Widget 和 Provider 分别拥有同一次验证操作。

必须实现 Single-flight：同一账号、同一恢复事务的重复验证请求共享结果。

### 职责 2：BrowserSessionHost

统一后台与可见 WebView 的生命周期。

优先复用仓库当前的 `flutter_inappwebview`，参考：

https://inappwebview.dev/docs/webview/headless-in-app-webview/

https://inappwebview.dev/docs/webview/keep-alive/

评估：

- 是否可复用原生浏览器实例。
- 是否能将 Headless WebView 转为可见 WebView。
- Android 上该功能是否可靠。
- 转换时 Cookie、代理、导航和 JavaScript 状态是否连续。
- 是否存在重复创建或资源泄漏。

理想情况：

```text
后台浏览器自动验证
        |
        +-- 成功 --> 会话确认 --> RFY
        |
        +-- 需要用户交互
                    |
                    v
            展示当前浏览器
                    |
                    v
               用户完成验证
                    |
                    v
            继续原恢复事务
```

**不要把复用同一个原生实例作为未经验证的强制前提。**

如果插件或 Android 实际行为不支持可靠转换，可采用共享 Cookie Store 加显式导航状态迁移的替代方案，但必须测试状态一致性。

不应长期无条件驻留隐藏浏览器。

### 职责 3：SessionEvidenceObserver

从“加载事件触发最终判定”改为“收集证据后判定”。

关注：

- 页面导航开始和结束。
- JavaScript 页面状态变化。
- SPA 导航。
- CSRF 出现。
- 身份标记出现。
- 明确的匿名证据。
- 明确的用户交互要求。
- 主框架网络错误。
- WAF 或中间页面。
- 页面长期不稳定。

使用：

- `onLoadStart`
- `onLoadStop`
- `onUpdateVisitedHistory`
- `UserScript`
- `evaluateJavascript`
- 必要的 JS Bridge
- 有界稳定性采样

不能仅凭某次 `onLoadStop` 或固定三次页面采样决定最终身份。

采样必须有总预算、事件去重、来源校验、生命周期清理和完成条件，不允许无限轮询。

### 职责 4：SessionDecisionEngine

建立可独立单元测试的纯逻辑状态机。

建议身份状态：

```text
restoring
observing
verified
inconclusive
interactionRequired
signedOut
blocked
```

核心规则：

1. 本地 OAuth 账号不能直接授予 Web 登录状态。
2. Cookie 和 CSRF 是候选证据，不是单独的认证证明。
3. 页面信息缺失不能直接转换为 signedOut。
4. 不确定状态不能覆盖已经确认的登录身份，但已确认身份也不能无限期忽略新的明确失效证据。
5. 旧 generation / accountEpoch 的结果不能更新当前状态。
6. 明确登出与服务器明确拒绝须被正确处理。
7. WAF 和网络失败不能伪装为已登出。
8. 认证证据必须具有明确来源、时间和适用账号。
9. 任何浏览器事件不应绕过统一状态转换入口。
10. 需要用户交互时，应进入可恢复状态，而不是无限尝试自动登录。

必须明确区分 `verified`、`inconclusive` 与 `signedOut` 的证据条件。

### 职责 5：SessionRepository

负责：

- 原生 Cookie Store。
- 已持久化 Cookie 快照。
- OAuth 账号绑定。
- Cookie 恢复和安全写入。
- Cookie 轮换。
- 账号切换隔离。
- 已确认有效快照保留。

优先使用 Android 原生 CookieManager 作为当前浏览器 Cookie 来源。

持久化快照只承担恢复职责。

不得在当前 Cookie 仍有效时无条件覆盖。

写入应串行化，保留 Domain、Path、Secure、HttpOnly、有效期等元数据。

不得持久化无必要的敏感副本，且所有凭据存储必须符合平台安全存储要求。

### 职责 6：PersonalizedFeedCoordinator

统一管理推荐请求。

它不负责判断用户是否登录，只消费已验证的 Web 会话状态和用户操作意图。

区分：

```text
session_recovered
initial_load
user_refresh
resume_refresh
cookie_context_changed
network_recovered
retry_after_failure
```

应提供：

- Single-flight。
- 请求所有权。
- 请求版本控制。
- Account Epoch 隔离。
- 真正的请求取消（适用时使用 Dio CancelToken）。
- 旧结果丢弃。
- 可解释的重新请求。
- 缓存与实时结果协调。

普通 Cookie/CSRF 轮换不应天然等同于账号切换或整个 Provider 重建。

请求是否过期，应结合认证上下文和具体事务判断，而不是简单比较所有 Cookie 指纹。

---

## 5. 重点解决 RFY 重复请求

v0.5.13 日志表明：

```text
rfy-4 transport success
items=24
但未 accepted

rfy-5 transport success
items=24
随后 accepted
```

需要建立清晰的请求生命周期：

```text
created
queued
in_flight
transport_succeeded
validated
accepted / discarded
completed
```

每次请求携带：

```text
recoveryId
requestId
accountEpoch
sessionGeneration
credentialRevision
triggerReason
```

每次废弃结果必须记录原因，例如：

```text
discardReason=account_changed
discardReason=session_superseded
discardReason=credentials_changed
discardReason=newer_request_won
discardReason=provider_disposed
```

不得简单记录请求成功或失败后就结束诊断。

需要检查一个特别重要的竞争：

**网页恢复时 Cookie 或 CSRF 发生轮换，旧请求已经成功返回，但会话状态随之改变，导致结果被丢弃，又启动第二个 RFY。**

这只是重点假设，必须通过证据确认。

预期行为：

- 同一事务只有一个有效首页请求所有者。
- 已成功获得的数据若仍满足账号、会话与响应正确性要求，不应无故丢弃。
- 认证上下文确实失效时应安全废弃。
- 用户主动刷新仍能正常发起新请求。
- 失败后能够重试。
- 账号切换不能出现交叉数据。

---

## 6. 缓存保持独立

现有 `ArtworkFeedCacheStore` 已具备：

- 账号隔离。
- 有界缓存。
- 原子写。
- 损坏或版本不符处理。
- 缓存时效记录。

优先保留这些有效实现。

必须保证：

- 缓存不阻塞实时请求。
- 缓存不能证明会话健康。
- 旧缓存不能冒充实时个性化结果。
- 账号切换后不显示其他账号的数据。
- 请求失败时可以保留可用旧内容。
- 缓存读取和写入失败不能破坏登录恢复。

不要因为本次会话架构调整而无意义地重写整个缓存系统。

---

## 7. 工程实施顺序

### Phase 0 — 生产证据闭环

在动手进行大规模重构前：

1. 检查实际代码、历史 PR 与已有测试。
2. 还原 08:07 日志涉及的调用链。
3. 找到 Headless 探测提前结束的所有路径。
4. 找出 RFY 结果丢弃和重新请求的实际触发点。
5. 补全 AppLogger 脱敏日志。

特别要求：

- 在 Release 构建中也能记录必要的探测日志。
- 日志区分页面未初始化、解析失败、明确匿名、主框架错误、超时、挑战页和正常关闭。
- 不记录 Cookie 值、Token、CSRF 原文、用户隐私内容。
- 单次恢复流程有统一 recoveryId。

如果必须依赖 Android 真机才能区分多个假设，请完成其他独立工作，同时交付具有明确观测目标的诊断 APK。

**不要跳过本阶段直接猜测根因。**

### Phase 1 — 统一浏览器与证据体系

- 将页面观察与状态判断分离。
- 统一 Headless、可见 WebView 的证据语义。
- 修复 CSRF 存在但用户名未初始化时的提前结束。
- 覆盖多次导航、SPA 页面变化、挑战中间页和超时。
- 明确浏览器实例所有权及资源释放。

### Phase 2 — 会话恢复协调器

- 统一冷启动与会话恢复入口。
- 减少多个模块各自触发的验证请求。
- 引入单次恢复事务和 accountEpoch。
- 明确状态转换、请求归并和用户交互回退。
- 保留已有 API 和测试契约，尽量渐进迁移。

### Phase 3 — RFY 请求治理

- 建立请求所有权。
- 明确自动恢复和主动刷新的不同语义。
- 定位并修复 `rfy-4` → `rfy-5` 同类竞争。
- 添加废弃原因与触发来源日志。
- 在安全前提下避免重复请求。

### Phase 4 — 回归测试

完整运行：

```bash
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

不得删除原有测试或为了通过测试而修改断言的业务含义。

必须增加测试：

1. HTML 有 CSRF，但用户身份尚未初始化。
2. 页面没有 CSRF，随后通过异步初始化得到身份。
3. SPA 导航不触发新的 onLoadStop。
4. 连续挑战中间页后进入已登录首页。
5. 真实匿名与页面解析失败严格区分。
6. Headless → Visible 迁移及回退逻辑。
7. Cookie 恢复与账号信息加载竞争。
8. Cookie/CSRF 轮换与请求完成竞争。
9. 多处同时触发 session check。
10. 同一恢复事务的 RFY Single-flight。
11. 成功网络响应被错误丢弃的场景。
12. 失败释放请求所有权并支持重试。
13. 前后台恢复、代理失效及恢复。
14. 账号切换与陈旧请求返回。
15. 缓存展示、有效性和账号隔离。
16. 浏览器销毁后无 Timer、回调或异步泄漏。

优先使用可控的假浏览器、事件序列和状态机单测，不依赖真实 WAF 才能运行自动化测试。

同时保留真实 Android 集成测试能力。

---

## 8. Android 真机验收

当前 v0.5.13 已被真实测试判定：

```text
Code Verified: PASS
Release Verified: PASS
Android Verified: FAIL
Original Incident Verified: FAIL
```

本次修改完成后，必须重新验收。

核心场景：

### A. 保留账号冷启动

- 不卸载 App。
- 不清除数据。
- 不清除 Cookie。
- 不重新登录。
- 使用修复后的正式 APK 覆盖升级。
- 强制停止并重新打开。
- 直接进入推荐页。
- 至少连续测试 10 次。

### B. 自动恢复

- 原始 Web 会话仍然有效时，应自动完成会话确认。
- 不要求用户每次重新打开登录页。
- RFY 返回真实个性化内容。
- 不发生无限转圈和无限验证。

### C. WAF 场景

- 如果实际出现挑战页面，验证自动等待后续导航。
- 如果网站要求人工操作，正确展示当前认证流程。
- 不通过模拟测试假装真实 WAF 已通过。
- 不尝试绕过第三方网站安全机制。

### D. 请求去重

- 记录每次 RFY 的逻辑事务和 HTTP 传输。
- 正常自动恢复不应无故重复请求首页。
- 所有额外请求都要有明确的 triggerReason。
- 成功返回但丢弃的结果必须说明原因。

### E. 网络恢复

- 代理断开与恢复。
- 网络超时。
- App 前后台切换。
- 缓存存在与不存在。
- 账号切换。

每个场景必须给出 PASS / FAIL / PENDING。

如果没有 Android 真机，不能宣布 Original Incident Verified。

---

## 9. 提交、PR、CI 与 Release

遵循仓库现有 GitHub Actions、ReleaseGraph 和 release-please 体系。

执行：

1. 建立独立修复分支。
2. 分阶段提交实现及回归测试。
3. 更新中英文认证架构文档。
4. 更新对应 regression 文档。
5. 创建 PR。
6. 验证 CI。
7. 按仓库现有发布门禁推进合并。
8. 通过正式 Release 工作流构建 Android APK。
9. 验证版本、Tag、Release 资产及 SHA256。
10. 核对 GitHub Pages 及下载地址。

不得跳过 CI、伪造设备日志或修改已发布 Tag。

优先利用 GitHub Runner 构建，不在未经用户允许时下载数 GB 的本地 Android SDK/JDK。

如权限或安全审批阻塞，准确报告，并保留代码和提交。

---

## 10. 工程约束

**必须遵守：**

- 不再通过增加固定重试次数、延长超时来掩盖架构问题。
- 不把 HTTP 200、OAuth 有效、Cookie 存在和 Web 登录成功混为一谈。
- 不将缺失的身份标记视为明确退出登录。
- 不将匿名通用推荐冒充个性化推荐。
- 不在多个 Widget 和 Provider 中维护相互竞争的恢复事务。
- 不让普通 CSRF/Cookie 轮换无条件触发 Provider 重建。
- 不让缓存阻塞真实推荐。
- 不因为不确定结果删除有效 Cookie。
- 不无限后台运行 WebView。
- 不引入不必要的事件总线、复杂框架或额外服务。
- 不扩展下载、搜索、图库等与本问题无关的功能。
- 不在缺乏实际证据时把设计假设写成已证实根因。
- 不绕过 WAF，也不尝试获取或伪造不属于当前用户的登录状态。
- 保留可回滚性、兼容性和全部原有测试。

可以进行有充分理由的架构重构，但应坚持**最小必要结构变化与清晰职责边界**，而非为了重构而重构。

---

## 11. 最终交付

输出可核验报告：

### A. Root Cause

区分已确认根因、证据、仍需真机证实的假设。

### B. Architecture

提供新旧流程对比、模块职责、状态转换与请求所有权说明。

### C. Implementation

列出实际修改文件、关键设计决策、Commit SHA。

### D. Tests

列出实际执行命令、测试数量、通过和失败结果。

### E. Diagnostics

给出恢复事务日志样例、RFY 请求追踪与结果丢弃原因。

### F. Release

列出 PR、版本、Tag、Release URL、Actions Run、APK 资产。

### G. Deployment

列出 GitHub Pages 与下载链接验证结果。

### H. Acceptance

明确区分：

```text
Code Verified
Release Verified
Android Verified
Original Incident Verified
```

### I. Remaining Risks

列出未覆盖的设备、WAF、账号和网络环境，以及仍依赖人工验证的事项。

---

## 12. 最终目标与执行指令

**本次任务的成功标准不是代码编译成功，也不是单元测试全绿，而是建立一个长期稳定、可解释、可维护的 Web 会话恢复架构。**

实际表现必须是：

1. 已登录用户冷启动时尽可能自动恢复 Web 会话。
2. 页面异步加载、挑战跳转和 CSRF 轮换不会导致应用自行误判身份。
3. 无法确认身份时不误判登出、不丢失已有凭据。
4. 需要人工操作时可平滑进入认证页面，不重复创建无意义的登录事务。
5. 会话恢复后只进行必要的推荐网络请求。
6. 所有重复请求、结果丢弃及状态转换均有明确证据。
7. 缓存、代理及账号切换不破坏上述逻辑。
8. 真实 Android 原始故障场景能被重新验证。

**现在立即从 GitHub 最新代码、v0.5.13 生产故障日志和浏览器会话状态差异开始执行。**

先建立可验证的根因假设和实施计划，然后直接开展代码修改、回归测试与交付。

不要重复此前已完成的补丁工作，不要仅通过增加重试参数宣称修复成功，也不要在没有真机证据时提前宣布问题彻底解决。

在有真实阻塞前，连续推进所有可以执行的工作；保持简洁的阶段性总结，控制上下文消耗，最终交付可复现、可审计的结果。

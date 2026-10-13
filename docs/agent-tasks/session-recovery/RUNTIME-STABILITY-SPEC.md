# DAViewer P0：运行期会话误判、分页跳转登录及个性化推荐误报的系统性修复

## 一、任务目标

仓库：https://github.com/redtidev1918/DAViewer

你是一名熟悉 Flutter、Riverpod、Android WebView、Dio、异步并发、认证协议与分页状态管理的高级工程师。

本任务不是单纯修复一个提示框，而是系统性解决 DAViewer 在**已经成功登录并自动恢复会话之后，运行过程中仍可能错误进入登录恢复状态**的问题。

用户提供了两个现象：

1. **自动登录恢复已经成功，推荐内容能够正常加载，但偶尔仍出现“个性化推荐可能未加载”之类的警告。**
2. **使用推荐信息流时，偶尔在加载下一页的过程中突然出现登录页面或要求重新登录。**

第二个现象比第一个更严重，可能涉及认证状态误判、分页请求副作用、后台验证竞争、路由更新或 UI 条件渲染。

需要全面检查相关调用链，不允许预先将故障限定为 UI 文案或某个 Provider。

**目标：有效会话在浏览、分页、刷新、进入详情、后台恢复等正常操作下保持稳定；真实失效能够正确识别；临时异常不会错误地将用户踢回登录界面。**

要求实际完成调查、复现、修复、测试和交付，不要只输出设计建议。

---

## 二、现有生产证据

2026-10-13 23:44–23:46 Android 真机日志表明：

```text
23:44:40
personalized session:
degraded -> usable
source=rfy-response
generation=3

rfy-3
triggerReason=user_refresh
phase=accepted
items=24
degraded=false

rfy-4
triggerReason=pagination
phase=accepted
items=24
genericFallback=false

rfy-5
triggerReason=pagination
phase=accepted
items=24
genericFallback=false

rfy-6
triggerReason=pagination
phase=accepted
items=24
genericFallback=false

rfy-7
triggerReason=pagination
phase=accepted
items=23
genericFallback=false

rfy-8
triggerReason=user_refresh
phase=accepted
items=24
genericFallback=false

rfy-9
triggerReason=pagination
phase=accepted
items=24
genericFallback=false
```

这段成功日志中：

- `provider=1`，没有发现 Provider 重建。
- `accountEpoch=1` 保持稳定。
- `sessionGeneration=3` 保持稳定。
- `credentialRevision=1` 保持稳定。
- `credentialsChanged=false`。
- 分页累计达到 119 项。
- 手动刷新后正确重置第一页及分页游标。
- 所展示的请求均完成 `accepted`。
- Cookie、OAuth 和网络在此期间可以正常使用。

**注意：这是成功场景日志，不是偶发跳登录时的失败日志。**

不能因为这一段成功就认定分页完全没有问题，也不能通过这些日志确定偶发故障根因。

必须能够复现或捕获失败时的状态转换。

---

## 三、已知源码风险点

以下是已经从 DAViewer 源码确认存在的机制，但它们是否为本次事故根因仍需验证。

### 1. 每次 RFY 分页可能触发会话检查

`lib/features/home/home_providers.dart` 中，推荐请求进入传输前会调用会话检查门禁：

```dart
await ref
    .read(webSessionStatusProvider.notifier)
    .check(
      force: ref
          .read(personalizedSessionStatusProvider.notifier)
          .cookieChanged(currentHeader),
    );
```

必须查清：

- 有效会话是否复用最近一次服务端认证结论。
- 每次分页是否有可能发生不必要的真实浏览器验证。
- Cookie 轮换是否触发强制检查。
- 认证检查是否与分页中的网络请求并发竞争。
- 已成功的首页请求是否可能被后续失败的复核覆盖。

### 2. 网络响应能够触发新的会话复核

`lib/core/auth/web_session_coordinator.dart`

其 Dio 拦截器可能因为以下信号发起复核：

- HTTP 401。
- HTTP 403。
- `/users/login` 重定向。
- `mature_loggedout`。
- 周期性定时器。
- App 恢复前台。

需要判断：

**资源请求失败、内容限制、代理/WAF 403、特定作品权限不足，是否有机会间接导致全局 Web 登录状态被判为 anonymous？**

HTTP 401/403 本身只能作为对应请求的失败事实，不能无条件推断整个 Web 会话已经退出。

### 3. 真实浏览器 anonymous 可以触发权威登出

`lib/core/auth/web_session_verdict.dart`

当前的 `realBrowserProbe` anonymous 结果可以直接转换为 `WebSessionStatusState.anonymous`。

这是高风险边界。

必须调查：

- 页面尚未初始化却被判匿名。
- WAF 页面被误判匿名。
- 重定向中间态被判匿名。
- 身份标记读取错误。
- 网络代理瞬时异常。
- Cookie 写入/读取并发。
- 旧探测结果返回。
- 账号代际或身份时代发生变化。

注意，不能简单废除真实匿名证据的权威性。应精确定义何种浏览器证据足够可靠，以及何种情况属于 `unverified/unavailable`。

### 4. 本地 Cookie 状态也能改变全局登录判定

检查：

```text
lib/core/auth/web_session_status.dart
lib/core/auth/web_session_controller.dart
lib/core/data/web_session.dart
```

尤其关注：

- 临时读取不到 Cookie Header。
- Cookie 尚未恢复完毕。
- Cookie Store 返回部分 Cookie。
- 用户名和 Cookie 快照暂时不一致。
- Cookie 补全、轮换及持久化竞争。

任何暂时不可读取状态都不能未经适当证据仲裁就视为真实退出登录。

### 5. 推荐 UI 可能因会话状态改变而直接显示登录入口

`lib/features/home/home_screen.dart`：

```dart
final webSessionDead = ref.watch(
  webSessionStatusProvider.select(
    (status) => status.needsLogin,
  ),
);
```

当 `needsLogin` 为 true，推荐页可能直接使用登录恢复 UI 替换信息流。

这意味着用户描述的“突然跳登录”可能有三种本质不同的表现：

1. GoRouter 真的导航到了 `/web-login`。
2. 仍处于首页路由，但推荐内容被登录恢复组件替换。
3. 全局提示或错误操作展示登录入口，给人造成跳转的观感。

**必须通过真实路由变化、Widget 状态和用户操作日志区分。**

不要把三种情况混为一谈。

### 6. `vespa_content_group=2` 判据尚未经协议确认

`lib/core/auth/personalized_session_status.dart`

当前 `rfyCursorSignalsGenericFallback()` 将游标中的 group 2 当作疑似通用内容信号。

但：

`docs/regressions/022-degraded-rfy-empty-home.md`

已经记载：服务端确认已登录的会话同样可能得到 group 2。

需要重新审查：

- group 2 是否导致错误降级。
- 降级是否诱发额外认证检查。
- 额外检查是否可能影响正在运行的分页。
- UI 是否因为弱证据显示误导性提示。
- 一次失败的分页是否覆盖整个推荐能力状态。

不要擅自猜测 DeviantArt 私有游标的协议语义。

---

## 四、全面调查范围

本任务不限制为少数 UI 文件。必须从以下六条链路展开。

### A. Web 会话生命周期

检查：

```text
web_session_status.dart
web_session_verdict.dart
web_session_verifier.dart
web_session_controller.dart
web_session_refresher.dart
browser_session_observer.dart
web_session_coordinator.dart
media_session_signal.dart
```

追踪：

```text
healthy
 -> verification triggered
 -> evidence collected
 -> verdict resolved
 -> state mutated
 -> UI/router affected
```

重点找到运行中 `healthy → anonymous/stale/locked/unverified/unavailable` 的全部路径、证据强度和副作用。

### B. RFY 分页请求生命周期

检查：

```text
home_providers.dart
artwork_feed_controller.dart
personalized_request_policy.dart
request_gate.dart
```

追踪：

```text
scroll_near_bottom
 -> pagination requested
 -> session gate
 -> HTTP transport
 -> response validation
 -> request ownership
 -> cursor update
 -> state commit
```

特别检查：

- 请求期间身份状态被后台探测改变。
- 旧请求完成后错误覆盖新的会话状态。
- 请求超时与正常完成竞争。
- CancelToken 取消旧请求时产生错误副作用。
- 旧游标、重复游标及分页末尾异常。
- 分页请求失败导致第一页或整页被替换。
- Cookie/CSRF 轮换引起错误的 credentials_changed 判断。

### C. 网络响应与认证信号

检查所有 HTTP 拦截器和非 Dio 媒体错误上报。

区分：

- 全局会话失效。
- 作品需要登录。
- R18/成熟内容限制。
- 付费内容限制。
- 地区限制。
- 资源 CDN 403。
- WAF 或代理 403。
- 单个 API 请求失败。
- 临时网络故障。

一个资源失败不能在没有进一步可靠证据的情况下变成整个账户退出登录。

### D. Router 与 UI

检查：

```text
lib/app/router.dart
lib/features/home/home_screen.dart
lib/shared/widgets/app_notice_host.dart
lib/features/home/recommended_degraded_banner.dart
lib/features/web_login/web_login_screen.dart
```

对每一次登录 UI 出现，必须区分：

```text
actual_navigation
feed_content_replaced
global_notice
error_action
interactive_recovery
```

检查 GoRouter 的重定向来源、导航触发者及是否存在意外自动 push/go。

### E. 个性化推荐能力与告警

检查推荐状态是否把以下概念混在一起：

- 网页身份是否有效。
- RFY 请求是否成功。
- 内容是否确实个性化。
- 单页响应是否疑似通用内容。
- 旧的降级事件是否已经恢复。
- 当前列表是实时内容还是缓存。

允许出现 `unknown`，不能强迫所有不确定状态都转为 `healthy` 或 `degraded`。

告警应与可靠证据和当前事件对应，避免历史警告残留。

### F. 生命周期与并发调度

覆盖：

- 启动自动恢复。
- 定时验证。
- 前后台切换。
- 首页刷新。
- 滚动分页。
- 图片与视频资源错误。
- 进入作品详情并返回。
- Cookie 自动轮换。
- WAF 挑战。
- 账号切换。
- Provider 重建与销毁。

检查同一时刻存在多个验证触发时，是否真正合并为一个恢复事务。

---

## 五、需要建立的系统不变量

请以以下不变量审计现有架构，必要时进行有边界的重构。

### 不变量 1：弱证据不能使有效会话突然退出

HTTP 403、某个作品受限、WAF 中间页、短暂空 Cookie、解析不到用户名、网络异常，都不能单独成为全局匿名结论。

### 不变量 2：明确的会话失效仍必须生效

不能通过永远保持 healthy、永久延长验证租约或忽略所有认证失败来掩盖问题。

真实退出登录、明确身份不匹配以及可靠的服务端匿名证据，仍然必须正确触发恢复流程。

### 不变量 3：分页失败不得自动清空已经成功加载的内容

在没有可靠的全局失效证据时，分页失败应保留已显示作品及当前位置，并提供局部重试。

### 不变量 4：分页不能拥有全局会话登出的直接权限

分页可以报告异常和请求验证，但身份状态转换必须经过统一、可审计的认证判决。

### 不变量 5：旧事务不得覆盖新事务

任何探测、请求或事件提交时应验证账号时代、会话代际和对应事务的归属。

### 不变量 6：异常提示必须能够自动解除

真实恢复后，旧警告应消失，不应跨路由或跨请求复活。

### 不变量 7：有效账号不应被重复要求登录

除非收到足够可靠的新证据证明需要重新认证，否则用户不应因为正常分页或资源失败反复打开登录页面。

---

## 六、诊断与复现要求

本次最重要的工作之一是捕获**从正常分页到登录 UI 出现的完整因果链**。

为正式版增加必要且脱敏的结构化日志。

至少包括：

```text
eventId
recoveryId
requestId
transportId
accountEpoch
sessionGeneration
credentialRevision

triggerSource
endpointClass
httpStatus
redirectClass

previousWebState
nextWebState
evidenceSource
evidenceOutcome
decisionReason

feedPhase
paginationCursorFingerprint
feedItemsCount

uiTransition
navigationSource
routeBefore
routeAfter
```

其中：

- 不得输出 Cookie、CSRF、OAuth Token 或完整认证 URL。
- 对 401/403 记录资源类型与来源，不记录敏感查询字符串。
- 为认证复核记录是谁触发它。
- 为会话降级记录证据和判决理由。
- 为登录 UI 出现记录来源。
- 为 RFY 结果废弃记录原因。

期望能够直接从日志回答：

**哪一次分页请求、哪一个网络响应、哪一次认证复核，使原本正常显示的推荐页变成登录状态？**

必须建立失败场景的确定性模拟测试；如果仍无法复现真实故障，应交付可收集下一次事故证据的正式诊断能力，不得伪称已确认根因。

---

## 七、必须新增的测试

### 认证证据测试

1. healthy 状态收到资源 CDN 403。
2. healthy 状态收到 Web API 403。
3. healthy 状态遇到 WAF 挑战。
4. healthy 状态暂时读取不到 Cookie。
5. 后台探测页面尚未初始化。
6. 真实浏览器返回明确匿名。
7. 用户真正退出登录。
8. 账号在旧探测返回前发生切换。

要求覆盖正确保留、降级和失效，而不是一律 healthy。

### 分页并发测试

1. 正常登录状态下连续加载多页。
2. 分页期间周期性认证检查启动。
3. 分页期间 App 前后台切换。
4. 分页期间 Cookie/CSRF 轮换。
5. 分页过程中某个媒体资源收到 403。
6. 分页接口自身收到 401/403。
7. 分页超时但已有作品存在。
8. 旧分页返回时新的首页刷新已完成。
9. 同一游标被重复触发。
10. 认证复核与分页返回顺序交错。

要求证明在缺乏可靠登出证据时，已有列表不被登录 UI 替换。

### 提示与路由测试

1. 自动恢复成功后没有误报警告。
2. group 2 游标不单独导致错误登录提示。
3. `degraded → usable` 后警告消失。
4. 正常分页不触发 `/web-login` 自动导航。
5. 局部网络失败不触发全局登录恢复 UI。
6. 真正失效时能够正确显示恢复入口。
7. 页面切换后旧提示不重新出现。
8. 用户关闭警告后，新发生的独立故障仍能提示。

必须测试真实 Widget 与 GoRouter 行为，而不是仅验证纯函数返回值。

---

## 八、修复策略

不要预先规定只允许修改某几个文件。

根据调查结果，允许：

- 修复认证判决策略。
- 重构认证检查与分页请求之间的责任边界。
- 改善 WebSessionCoordinator 的信号过滤。
- 修复 Cookie 和身份观测的竞争。
- 调整健康租约及不确定状态语义。
- 修复状态清除和订阅生命周期。
- 调整错误 UI 和路由之间的责任。
- 完善 Request Ownership。
- 修正未经验证的 RFY 降级判据。

但必须遵守：

**根因需要多大范围，就修改多大范围；不要为了最小改动而保留架构缺陷，也不要为了全面重构而重写正常模块。**

禁止以下伪修复：

- 删除所有登录提示。
- 将所有认证状态强制设置为 healthy。
- 无限延长登录验证有效期。
- 忽略真实登出。
- 简单增加重试次数。
- 强制重新登录解决分页。
- 清除用户 Cookie 或应用数据。
- 每次异常重新创建 WebView。
- 无条件重建整个推荐 Provider。
- 用固定延迟隐藏警告。
- 将“测试通过”冒充真实设备故障已经修复。

---

## 九、执行计划

### Phase 0：基线确认

读取仓库 `AGENTS.md`、当前 main、实际最新发布版本、相关回归文档以及本任务全部代码路径。

保留工作区已有修改。

不要依据旧版本代码实施修复。

### Phase 1：系统性审计

输出可验证的会话与分页调用图，枚举所有导致登录 UI 出现的路径。

将已确认事实、代码设计风险、仍未证实的假设分开。

### Phase 2：确定性故障复现

使用 Fake Dio、可控制的 Browser Probe、ProviderContainer、Widget Test 和 GoRouter Test 构造交错事件。

优先复现“健康会话分页时突然出现登录 UI”。

### Phase 3：实施修复

按照根因调整认证证据、会话状态、分页请求及提示逻辑。

确保自动登录恢复继续正常。

### Phase 4：完整回归

执行：

```bash
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

执行仓库现有的 SDK 集成测试、Android 构建检查及相关 CI。

### Phase 5：PR 与发布

创建独立修复分支及 PR，更新必要的中英文文档和 regression 记录。

确保 CI 通过。

发布按照仓库既定审批与工作流进行，不修改历史 Tag，不跳过安全和质量检查。

### Phase 6：真机验收

保留账号和 Cookie 覆盖升级。

至少验证：

- 10 次冷启动自动恢复。
- 长时间持续滚动分页。
- 快速连续滑动。
- 分页时进入详情并返回。
- 分页时前后台切换。
- 网络、代理短暂中断及恢复。
- 真实登出和重新登录。
- 正常场景无虚假警告。
- 真实错误能够恢复。

不能通过模拟测试宣布原始偶发故障已经在真机解决。

---

## 十、交付报告

必须输出以下内容：

### A. Root Cause

每个故障对应的证据、触发链路及根因置信程度。

分别回答：

1. 为什么正常登录后会出现推荐异常警告？
2. 为什么分页过程中可能突然出现登录 UI？
3. 这是实际导航、局部 UI 替换，还是全局通知？
4. 是否存在错误的认证状态转换？
5. 是否存在分页与后台认证复核竞争？

未确认的问题明确标注 UNVERIFIED，不允许虚构。

### B. Architecture

说明修复前后的认证、分页、UI 状态所有权和交互关系。

### C. Implementation

列出修改文件、Commit SHA、PR URL 以及关键设计选择。

### D. Regression

列出新增测试、自动化复现结果和完整测试通过情况。

### E. Android Evidence

提供正式设备验收结果及必要的脱敏日志。

### F. Release

提供适用的 CI、Tag、Release、APK 资产及校验结果。

### G. Remaining Risks

列出仍可能由 DeviantArt WAF、协议变化、设备 WebView 差异造成的不可控风险。

严格区分：

```text
Code Verified
CI Verified
Release Verified
Android Verified
Original Incident Verified
```

没有真实设备证据时保持 PENDING。

---

## 十一、最终验收目标

修复完成后，应满足：

1. 自动登录恢复继续正常。
2. 有效会话下，个性化推荐能够正常加载。
3. 分页、刷新、进入详情和前后台切换不会无故要求重新登录。
4. 临时网络、WAF、Cookie 读取异常不会被错误识别为已登出。
5. 真正的认证失效仍然能够正确识别。
6. 已加载内容不会因为单页失败而丢失。
7. group 2 等未经确认的信号不会独立造成用户可见的误报。
8. 恢复成功后过期提示自动消失。
9. 所有全局登录状态变化、登录 UI 出现及推荐请求废弃均可从日志追溯。
10. 用户不需要通过反复手动登录来恢复正常使用。

**现在开始实际执行。**

不要只修复警告文案，也不要未经调查就重构整个项目。

首先追踪“运行期 healthy 会话在分页时可能转为 needsLogin”的所有因果路径，再针对已经证实的问题实施必要的系统性修复，最终完成回归测试和可审计交付。
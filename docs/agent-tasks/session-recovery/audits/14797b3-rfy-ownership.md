# 14797b3 免真机代码审计:rfy/deviations 单飞与结果归属机制

- 审计对象:工作区代码(等于提交 14797b3,忽略 docs/ 与 clear/)
- 范围:个性化推荐请求(rfy/deviations)的 single-flight、transportId 终态、接受/丢弃判定、rfy-4 历史场景、恢复重发有界性、测试覆盖
- 方式:只读代码审计(无真机、无运行时证据);所有结论均出自下述 file:line 引用的代码
- 关联文件:`lib/core/feed/artwork_feed_controller.dart`、`lib/core/feed/personalized_request_policy.dart`、`lib/features/home/home_providers.dart`、`lib/core/data/request_gate.dart`、`lib/core/auth/web_session_status.dart`、`lib/core/auth/web_session_coordinator.dart`、`lib/features/home/home_screen.dart`、`lib/core/diagnostics/app_logger.dart`,以及 pub 缓存中的 DAKit(`dakit_web-0.2.5/lib/src/rfy_feed.dart`)

---

## Q1 首页单飞(single-flight)

**结论:OK。** 同一控制器内,同一首页最多只有一个在飞物理请求;允许第二个物理请求的条件全部有界,不存在并发重复物理传输。

### 证据

单飞原语(lib/core/feed/artwork_feed_controller.dart:90, lib/core/feed/artwork_feed_controller.dart:219-231):

```dart
Future<void>? _activeFirstPageFetch;            // :90
Future<void> _runFirstPageFetch({String reason = 'initial_load'}) {
  final active = _activeFirstPageFetch;
  if (active != null) return active;            // :221 已有在飞请求 → 直接 join
  ...
  tracked = _performFirstPageFetch().whenComplete(() {
    if (identical(_activeFirstPageFetch, tracked)) _activeFirstPageFetch = null; // :225-227
  });
  _activeFirstPageFetch = tracked;              // :229 同步赋值,无 await 竞态窗口
```

四个首页入口全部经 `_runFirstPageFetch`:`refresh()`(artwork_feed_controller.dart:163)、`forceRefresh()`(artwork_feed_controller.dart:186)、`recoverInitialPage()`(artwork_feed_controller.dart:208-217,结尾 `await _runFirstPageFetch(reason: 'session_recovered')`)、`refreshSilently()`(artwork_feed_controller.dart:336)。

RepositoryRequestGate 提供第二层同 key 去重(lib/core/data/request_gate.dart:整个 57 行文件;`load(key,...)` 对 `_inflight[key]` 已存在的请求返回同一 future)。首页的 gate key 含 revision(lib/core/feed/artwork_feed_controller.dart:129 `final key = '$_revision:${request.cursor ?? 'first'}:${request.limit}';`),每次首页尝试 revision 递增(artwork_feed_controller.dart:235 `final revision = ++_revision;`),所以首页的真正去重层是 `_activeFirstPageFetch`,gate 主要服务分页(同 cursor 的重复 loadMore 共享在飞请求,见测试 'duplicate loadMore shares one in-flight pagination request')。

provider 侧每个 `PageRequest` 绑定一个 `CancelToken`(lib/features/home/home_providers.dart:75-77),`cancelRequest` 按 request 精确取消(home_providers.dart:377 `cancelRequest: (request, reason) => requestTokens[request]?.cancel(reason)`)。

### 解释:什么时候同一首页可以有第二个物理请求

1. **上一个已结算(串行重发,有界)**:首页失败会释放所有权(artwork_feed_controller.dart:269-270 `_firstPageFetched = false; _firstPageContextKey = null;`),恢复边沿或用户重试可以再发。新请求与旧请求不并发。
2. **60 秒超时后的短暂收尾重叠(有界,物理传输已中止)**:`_fetchPage` 的 `onTimeout` 先窄取消再抛错(artwork_feed_controller.dart:135-149):
   ```dart
   onTimeout: () {
     gate.cancel(key);
     final cancel = cancelRequest;
     if (cancel != null) cancel(request, 'request_timeout');  // 窄取消:只取消本请求
     ...
     throw const DAKitException(... code: 'feed.request.timeout' ...);
   ```
   超时后旧闭包进入收尾(dio 收到 cancel,物理连接中止),新 refresh 可以立刻开新请求;旧 transport 的 CancelToken 已取消,不存在两个存活物理传输。超时本身有界(requestTimeout=60s,home_providers.dart:373)。
3. **provider 重建(账号身份变化,有界)**:重建条件是 `personalizedFeedSessionIdentity = (web.isLoggedIn, web.username)`(home_providers.dart:425-426),CSRF 轮换不触发。旧 provider `ref.onDispose` → `cancelRequests('provider_disposed')`(home_providers.dart:68),旧 token 全部取消;即便新旧 controller 有一个极短的交接窗口,旧物理传输被取消且其结果必以 `provider_disposed`/`account_changed` 落日志丢弃(见 Q3)。

`forceRefresh`(用户手势)也走单飞:在飞时它 join 而非并发(测试 'coalesces overlapping first-page refreshes':refresh+refresh+refreshSilently → calls==1)。

---

## Q2 transportId 与终态记录

**结论:OK。** 每次物理尝试有唯一 `transportId`(`rfy-<seq>-t<attempt>`),且每个 requestId 必有恰好一条终态(accepted/discarded/failed)+ completed 行;代码路径上不存在"发出请求后没有任何终态记录"的路径。

### 证据

每次物理尝试前置 `in_flight`、后置三种 transport 终态之一(lib/features/home/home_providers.dart:452-455, 481-489, 491-499):

```dart
trace('in_flight',
  'transportId=$requestId-t$attempt transportReason=${attempt == 1 ? 'owner_request' : 'retry_after_failure'} ...');  // :452-455
final response = await dio.get<Object?>(
  'https://www.deviantart.com/_puppy/dabrowse/networkbar/rfy/deviations',   // :459
  queryParameters: {'csrf_token': csrf, if (request.cursor != null) 'cursor': request.cursor},
  options: webSessionOptions(cookieHeader), cancelToken: cancelToken);       // :464-465 自有传输
final page = RfyFeedFetcher.parseJson(response.data);                        // :467 DAKit 纯解析器
...
trace('transport_succeeded', 'transportId=... items=... genericFallback=...'); // :481-489
...
} on Object catch (error, stack) {
  if (cancelToken.isCancelled) { trace('transport_cancelled', 'transportId=...'); rethrow; }  // :492-494
  trace('transport_failed', 'transportId=... failureReason=...');                              // :496-499
```

requestId 级 catch/finally 保证终态 + completed(home_providers.dart:357-371):

```dart
} on Object catch (error) {
  if (terminalOutcome == null) {
    final lost = ownershipLost();
    if (lost != null) trace('discarded', 'discardReason=$lost');      // :361
    else trace('failed', 'failureReason=${classifyFeedFetchError(error)}'); // :363
  }
  rethrow;
} finally {
  pendingTokens.remove(token); requestTokens.remove(request);
  trace('completed', 'outcome=${terminalOutcome ?? 'unknown'}');      // :370 兜底 'unknown'
}
```

- 取消/超时路径:`cancelRequest(request,'request_timeout')`(controller)→ `token.cancel` → dio 抛 cancel 异常 → `transport_cancelled`(home_providers.dart:492-494)→ rethrow → 外层 catch 里 `ownershipLost()` 经 `token.isCancelled` 分支返回取消原因(home_providers.dart:99-101)→ `trace('discarded', 'discardReason=request_timeout')` → completed。provider 销毁同理(cancelRequests('provider_disposed') → transport_cancelled → discarded)。
- 异常路径:`transport_failed` + warning(home_providers.dart:500-509)→ 返回 null → 重试一次后 `rfy.feed.unavailable` 抛出(home_providers.dart:271-275)→ catch `trace('failed')` → completed。
- 日志层不会吞终态:`AppLogger._write` → `debugPrint` + `_enqueueLine`(队列化文件写,失败仅 `catchError(_reportFileFailure)` 不抛,lib/core/diagnostics/app_logger.dart:105-122, 163-171)。

DAKit 侧证实"自有传输 + 公共解析器、无隐藏重试":`RfyFeedFetcher.fetch()` 含隐藏 400→CSRF 刷新重试(pub 缓存 dakit_web-0.2.5/lib/src/rfy_feed.dart:27-38),但 app 只调用其纯解析器 `parseJson`(rfy_feed.dart:58-76,无 HTTP);`webSessionOptions` 只是 headers/UA(dakit_web-0.2.5/lib/src/web_session_options.dart:12-19)。dio 默认无重试。

**残余(非缺陷)**:唯一"无终态"情形是 `await` 永不完成(如平台通道死锁、进程被 OS 直接杀死丢失最后一条队列写——app_logger.dart:178-179 注释明示)。这属于平台级风险而非代码路径缺陷,且可观测:`scripts/summarize_session_recovery.dart` 的测试(test/session_trace_summary_test.dart:7 'IDs are scoped per launch and incomplete/duplicate terminal facts stay visible')断言 `missingTerminal` 会显式呈现。

---

## Q3 接受/丢弃判定与静默丢弃

**结论:OK(无静默丢弃)。** 判定在 transport 成功后统一进行,比较项完整,每个丢弃分支都落 `discardReason` 日志并抛错。

### 证据:精确比较清单

裁决入口(lib/features/home/home_providers.dart:278-307):

```dart
final currentHeader = await webSession.cookieHeader();                       // :280
final degraded = rfyCursorSignalsGenericFallback(page.nextCursor);          // :281
final discardReason = personalizedResultDiscardReason(
  mounted: ref.mounted,                                                     // :283
  sameAccount: ref.mounted &&
      ref.read(webSessionControllerProvider).username == webSessionState.username, // :284-287 同账号
  sameEpoch: epoch == statusOwner.accountEpoch,                             // :288 账号纪元
  sameRequest: revision == requestRevision,                                 // :289 请求归属
  healthy: ref.mounted && ref.read(webSessionStatusProvider).isHealthy,     // :290 会话健康
  sameGeneration: generation == statusOwner.generation,                     // :291 会话代际
  sameCredentials: currentHeader == cookieHeader,                           // :292 全量 Cookie 头
  generic: degraded);                                                       // :293 generic 光标信号
final finalDiscardReason = ownershipLost() ?? discardReason;                 // :295
if (finalDiscardReason != null && finalDiscardReason != 'generic_fallback') {
  trace('discarded', 'discardReason=$finalDiscardReason credentialsChanged=${currentHeader != cookieHeader}'); // :298-301
  throw const DAKitException(... code: 'rfy.session.unverified' ...);
```

`ownershipLost()`(home_providers.dart:95-103)先判 transport 归属/硬失效:账号纪元(L96)、`ref.mounted`(L97)、请求 revision(L98)、`token.isCancelled`(L99-101,含取消原因)。策略纯函数(lib/core/feed/personalized_request_policy.dart:14-21)再按序判:mounted → account/epoch → request → healthy → (代际差 + generic) → (同代际 + Cookie 变) → generic:

```dart
if (!mounted) return 'provider_disposed';                    // :14
if (!sameAccount || !sameEpoch) return 'account_changed';    // :15
if (!sameRequest) return 'newer_request_won';                // :16
if (!healthy) return 'session_superseded';                   // :17
if (!sameGeneration && generic) return 'session_superseded'; // :18
if (!sameCredentials && sameGeneration) return 'credentials_changed'; // :19
if (generic) return 'generic_fallback';                      // :20
return null;                                                  // :21 → 接受
```

### 逐丢弃分支的日志核对(全部落日志)

| 分支 | discardReason | 日志位置 |
|---|---|---|
| provider 销毁 | provider_disposed | requireOwnership home_providers.dart:108 / catch :361 |
| 取消(超时等) | request_timeout / provider_disposed(cancel 原因) | transport_cancelled :493 + catch :361 |
| 账号/纪元变化 | account_changed | :108 / :298-301 |
| 新请求胜出 | newer_request_won | :108 / :298-301 |
| 响应时 session 不健康 | session_superseded | :298-301 / retry 中 :232 |
| 代际前进 + generic | session_superseded | :298-301 |
| 同代际 Cookie 轮换未验证 | credentials_changed | :298-301(附 credentialsChanged 标志) |
| generic 一律 | generic_fallback | :320 + warning 'rfy generic fallback rejected source=vespa_content_group_2' :321-325 + `recheckAfterWebSignal('rfy-generic-fallback')` :328-330 |

无论走哪条分支,finally 的 `trace('completed','outcome=...')`(home_providers.dart:370)必落。异常早退路径(dio 缺失 :127-133、未登录 :137-148、needsLogin :171-182、unverified :183-189)均被 catch 捕获 → `trace('failed')`(:363)→ completed。`_tryFetchRfy` 的 csrf/cookie 为空直接 return null(无物理传输,warning :441-447),不构成"响应被丢弃"。

**唯一"无声 return"**:控制器层的 revision 防御检查(artwork_feed_controller.dart:245, 257, 266, 306, 315 `if (!mounted || revision != _revision) return;`)。在单飞 + provider 层先行裁决的架构下,任何能到达控制器层的 page 都已通过 provider 的终判并 `trace('accepted')`;revision 不匹配在这些入口间不可达,属纵深防御而非静默丢弃路径。**RISK(信息级)**:若未来有人绕过 provider 直接喂 controller,这些 return 无日志——建议补一行 debug 日志(最小修复,非必须)。

---

## Q4 rfy-4 历史场景在 14797b3 下的走向

**结论:会被接受(trace('accepted','items=24')),不再是静默丢弃。**

### 场景映射

08:07:54 web session unverified→healthy(source=web-login)对应 `markHealthy` → `generation++` → `applyVerification`(lib/core/auth/web_session_status.dart:489-502;裁决入口 applyVerification :254-304,过期代际结果有 'verification result discarded ... reason=stale' 日志)。rfy-4 在飞,其代际快照是 transport 前读取的 `var generation = ref.read(webSessionStatusProvider.notifier).generation;`(home_providers.dart:200)。

响应到达(items=24,genericFallback=false)时逐条过判定:

- `mounted` ✓;`sameAccount` ✓(username 未变);`sameEpoch` ✓(账号纪元未变)→ 不是 `account_changed`
- `sameRequest` ✓(rfy-5 在 08:07:58 才出现;且在单飞下它会 join rfy-4 的在飞请求,根本不会成为第二个物理请求)→ 不是 `newer_request_won`
- `healthy` ✓(刚被 markHealthy)→ 不是 :17 的 `session_superseded`
- `sameGeneration` = false(恢复使代际前进),但 `generic` = false → **:18 不触发**(旧版正是在这里整条丢弃)
- `sameCredentials` = false(web-login 恢复可能轮换 Cookie),但 `sameGeneration` = false → **:19 不触发**(这正是"已验证新代际可采纳非通用响应"的设计)
- `generic` = false → :20 不触发
- `ownershipLost()` = null(纪元/mounted/revision/token 均正常)
- → `finalDiscardReason == null` → `trace('validated')`(:308-311)→ 非 degraded → `putAll` + **`trace('accepted', 'items=24')`**(:337-338)+ info 日志(:339-343)

端到端回归测试直接覆盖该场景:test/home_refresh_no_probe_test.dart:463 'verified same-account recovery adopts a successful in-flight response without second RFY'(在飞中轮换 Cookie + markHealthy → items 落地 + artworkStore 有值 + **rfy.calls==1**,无第二次请求);策略层 test/personalized_request_policy_test.dart 'verified same-account recovery adopts a usable old response'(generation:false, credentials:false → null=采纳)。

### 在 14797b3 下仍会保守丢弃(设计如此)且落日志的条件

1. 响应是 generic 且代际前进 → `session_superseded`(policy :18)
2. 同代际下 Cookie 轮换未经新代际确认 → `credentials_changed`(policy :19;测试 'unconfirmed credential rotation is still rejected'、'a cookie rotation during a feed request discards its result')
3. 任何 generic 响应 → `generic_fallback` + warning + 触发 `recheckAfterWebSignal`(home_providers.dart:319-335)
4. 响应时 session 已不健康 → `session_superseded`(policy :17)
5. 有更新的首页请求胜出 → `newer_request_won`
6. 账号或纪元变化(含离开又回来)→ `account_changed`
7. provider 销毁 / 请求被取消 → `provider_disposed` / 取消原因

以上每条都有 `discardReason=` 日志与 completed 行(Q3 表)。

**对历史 v0.5.13 的说明:无法从当前代码判定(CANNOT-DETERMINE)**——旧版本代码不在本工作区,审计无法直接复现当时的丢弃实现。可以确定的是:在 14797b3 的规则下,同类事件(代际前进 + 非通用 24 项 + 同账号)不再可能静默丢弃;若发生任何丢弃,日志必有 `discardReason` 与 `completed` 行,`summarize_session_recovery.dart` 亦会把 incomplete/duplicate terminal facts 显式呈现(session_trace_summary_test.dart:7)。

---

## Q5 会话恢复完成后的重复 RFY 请求有界性

**结论:OK(有界)。** 四重机制叠加,不存在无限循环重发。

### 证据

1. **恢复监听是边沿触发**:home_providers.dart:404-410
   ```dart
   ref.listen(webSessionStatusProvider, (previous, next) {
     if (previous?.isHealthy == false && next.isHealthy) {   // 仅 false→true 边沿
       unawaited(controller.recoverInitialPage());
   ```
   healthy→healthy 的状态对象更新(如同一代际内 server 重新确认)不触发;测试 'verification recovery automatically resumes a stopped initial feed'(home_refresh_no_probe_test.dart:349)断言恢复后 rfy.calls==1,再 markHealthy 不重载。
2. **recoverInitialPage 是条件动作**:artwork_feed_controller.dart:208-217——`!mounted || isLoading` 直接 return(在飞时 join 单飞);仅在 `staleContent`(items 非空且 lastRefreshError!=null)或 `failedInitialLoad`(items 空且 error!=null)时才 `_runFirstPageFetch('session_recovered')`。成功后 error/lastRefreshError 被清空、`_firstPageFetched=true`,此后恢复调用是 no-op。
3. **refresh() 幂等**:同一 session context(sha256(csrf+cookie),home_providers.dart:381-384 / feedSessionContextKey :519-522)下的重复 refresh 不发请求(artwork_feed_controller.dart:163-181;测试 'a repeat refresh in the same session context never refetches')。
4. **每 requestId 至多 2 次物理尝试**:attempt 1(owner_request)+ 失败后一次 attempt 2(retry_after_failure,home_providers.dart:201-258);attempt 2 前有 `check(force: true, browser: true)` 健康闸门(:227-238),不健康即 `trace('discarded','session_superseded')` 并终止。
5. **验证链自身有退避**:check 异常进入指数退避 30s/2m/10m(web_session_status.dart:537-546 `_setTransient`,backoff 数组);健康判定有 5 分钟租约(`_cacheDuration`)。失败→恢复→再失败的循环每圈都需要一次真实的 unverified→healthy 边沿(即一次成功的浏览器探针验证),节律由验证链而非 feed 代码决定。

前台恢复路径同样受控:home_screen.dart:202-227 仅在 `shouldRefreshPersonalizedFeedOnResume`(后台时长/路由/Tab/滚动位置策略)通过时 `refreshSilently()`;显式重试按钮先查 `wasEmpty && items.isNotEmpty → return` 与 `isLoading → return`(home_screen.dart:171-176)避免与恢复事务重复。

---

## Q6 测试覆盖

**结论:OK(覆盖良好),存在 4 个日志路径缺口(均为 P2 级观察,不影响行为正确性)。**

### 已覆盖的关键测试

策略层(test/personalized_request_policy_test.dart,8 个):

- 'stable verified response is accepted'——基线接受
- **'verified same-account recovery adopts a usable old response'**——rfy-4 策略层:generation:false + credentials:false → null(采纳新代际)
- 'same-account confirmation alone does not waste a usable response'
- **'unconfirmed credential rotation is still rejected'**——同代际 Cookie 轮换 → 'credentials_changed'(旧保守拒绝保留)
- 'account switch including away-and-back rejects stale response'——account/epoch:false → 'account_changed'
- 'newer request and disposed provider have explicit discard reasons'
- 'expired session cannot adopt a transport success'——healthy:false → 'session_superseded'
- 'generic old response cannot revive a cleared incident'——generation:false+generic → 'session_superseded';generic → 'generic_fallback'

端到端(test/home_refresh_no_probe_test.dart,766 行,使用 `_RfyAdapter`/`_HomeProbeAdapter`/`_FakeCookieManager` 假件):

- **'RFY trace has complete metadata and one terminal outcome'**(L270-347,含 verified rotation=false/true 两个变体)——断言 phases 按序包含 [created, queued, in_flight, transport_succeeded, accepted|discarded, completed]、恰好一个终态、每行含 recoveryId/accountEpoch/sessionGeneration/credentialRevision/triggerReason/transportId=、rotation 时 discardReason=credentials_changed
- **'verified same-account recovery adopts a successful in-flight response without second RFY'**(L463)——rfy-4 场景端到端:在飞中轮换 Cookie + markHealthy → 落地 + rfy.calls==1
- 'verification recovery automatically resumes a stopped initial feed'(L349)——恢复触发一次、后续 markHealthy 不重载(Q5)
- 'a cookie rotation during a feed request discards its result'(L446)——保守拒绝路径
- 'account change while waiting on Cookie read sends no obsolete transport'(L229,rfy.calls==0)、'account epoch changes invalidate away-and-back responses'(L486)
- 'generic signal is rejected even when identity verification succeeds'(L189)、'a late generic result cannot replace a newer same-account login'(L416)
- 'unknown stale Cookie is verified before accepting generic HTTP 200' / 'browser challenge blocks unverified recommendations without expiry'(L505)
- 'pull-to-refresh re-fetches rfy without a home-page verifier probe'(L567)、'explicit retry verifies despite automatic cooldown'(L385)、'an anonymous web-session verdict shows recovery, not generic content'(L710)

控制器层(test/artwork_feed_controller_test.dart):

- 'coalesces overlapping first-page refreshes'(L232)——单飞合并
- 'obsolete pagination timeout cancels only its own request'(L17)——窄取消
- group 'first-page ownership (session context)':'a repeat refresh in the same session context never refetches'(L491)/'a rotated session context refetches the first page'(L515)/'forceRefresh always fetches for an explicit user gesture'(L536)/'a failed first page releases ownership so retry refetches'(L552)
- 'a refreshed feed cannot join an old request for the same cursor'(L203)、'duplicate loadMore shares one in-flight pagination request'(L314)、'refresh supersedes old pagination (failure=false|true)'(L154)、'a stalled page fetch times out and later retries start fresh'(L340)

其他:test/personalized_feed_refresh_policy_test.dart(会话身份不含 CSRF、resume 策略分支);test/session_trace_summary_test.dart:7(日志汇总工具把 missingTerminal/multipleTerminals 显式呈现,IDs 按启动隔离)。

### 缺口

1. **超时/取消路径的 rfy 终态日志无测试**:`request_timeout` → `transport_cancelled` → `discarded(discardReason=request_timeout)` → `completed` 的日志序列未被任何测试断言(控制器层测了窄取消行为,但未断言 rfy trace 行)。
2. **attempt 2 的 transportId 无测试**:`transportId=rfy-N-t2 transportReason=retry_after_failure` 的重试日志路径(home_providers.dart:248-258)无覆盖。
3. **provider_disposed 终态日志无测试**:控制器有 dispose 行为测试,但 rfy 级 `discarded(discardReason=provider_disposed)` + completed 的 trace 序列未断言。
4. **恢复→失败→再恢复的循环有界性无显式测试**:现有测试覆盖单次恢复与"再 markHealthy 不重载",但"恢复成功→fetch 失败→再次恢复"的多圈行为无断言(由 Q5 的边沿触发 + 条件动作推理保证)。

---

## 总体结论

14797b3 的 rfy 单飞与结果归属机制在代码层面**达到设计意图**:single-flight 无并发重复物理传输;每次物理尝试有唯一 transportId 与必达终态日志;接受/丢弃判定比较项完整(账号纪元、请求归属、token 取消、同账号、健康、会话代际、全量 Cookie、generic 信号)且**每个丢弃分支都落 discardReason 日志,不存在静默丢弃**;恢复重发受边沿触发 + 条件动作 + 幂等 refresh + 每请求至多 2 次尝试 + 验证链退避五重限制,有界。rfy-4 历史场景(代际前进 + 非通用 24 项 + 同账号)在当前规则下会被接受并落地,且有端到端测试锁定该行为。

## 缺陷列表

| # | 级别 | 描述 | 位置 | 最小修复建议 |
|---|---|---|---|---|
| 1 | P2(观察) | 控制器层 revision 防御检查静默 return(单飞下不可达,纵深防御) | artwork_feed_controller.dart:245,257,266,306,315 | 补一行 `AppLogger.debug` 记录 revision mismatch;或维持现状并在注释注明依赖 provider 层裁决 |
| 2 | P2(测试缺口) | rfy 超时/取消路径、attempt-2、provider_disposed 的终态日志序列无测试断言 | test/home_refresh_no_probe_test.dart | 在现有 `_RfyAdapter` 假件上加 3 个 trace 断言测试 |
| 3 | P2(测试缺口) | 恢复→失败→再恢复多圈有界性无显式测试 | 同上 | 一个多圈恢复场景测试,断言 rfy.calls 计数与终态 |
| 4 | RISK(平台级) | 进程被 OS 杀死时最后一条队列日志写可能丢失(终态行缺失);`await` 永不挂死无兜底 | app_logger.dart:178-179 | 已由 summarize 工具的 missingTerminal 呈现缓解;无需代码改动 |
| 5 | RISK(信息级) | 同账号名但不同账号(理论上)可绕过 username 比较——由 accountEpoch 兜底,实际不可达 | home_providers.dart:284-287 | 无需改动(epoch 已覆盖) |

未发现 P0/P1 缺陷。

## 对 rfy-4 历史案例的代码层解释

**无法从代码判定(CANNOT-DETERMINE)**:v0.5.13 的实际丢弃代码不在本工作区,本审计无法复现其原始分支。基于当前代码可确定的对照结论:在 14797b3 规则下,同一事件序列(unverified→healthy 使代际前进 + 24 项非通用响应 + 同账号同纪元 + 无更新请求)会走 `personalizedResultDiscardReason` 的 `return null` 路径被接受(transport 前代际快照 home_providers.dart:200,裁决 :282-295,接受 :337-343),并由测试 home_refresh_no_probe_test.dart:463 锁定;任何其他丢弃均必有 `discardReason=` 日志与 `completed` 行。若生产日志再次出现"transport success 但无 accepted"的形态,只可能是:进程被杀丢失末行(可由 summarize 工具的 missingTerminal 识别)、或旧版本代码仍在运行(buildRevision 核对)。

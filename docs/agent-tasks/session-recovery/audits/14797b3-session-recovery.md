# 14797b3 Android 会话恢复审计(免真机代码审计)

- **审计对象**:工作区代码 = 提交 `14797b3`(分支 `codex/android-session-recovery`)。审计仅基于亲自读到的代码,未做任何修改、未运行真机。
- **背景**:v0.5.13 原始故障(OAuth whoami=200 但 Web Session 长时间 unverified、重复 RFY、rfy-4 成功响应被丢弃);候选 `12aaeac` 真机 FAIL(主动退出后重新登录失败:完成 `/_sisu/do/step2` 但 OAuth 回调未见、账号不刷新、不返回首页、RFY 报 Web Session 不可用);候选 `3d62b45` 真机 FAIL(启动卡死);`14797b3` 加入 12s 启动 deadline 门。
- **判定口径**:OK / DEFECT(P0|P1|P2)/ RISK / CANNOT-DETERMINE。P0=直接造成本次故障级后果;P1=现实可触发路径下破坏核心保证;P2=边角/自限,应修但不阻塞验收。

---

## 问题 1:启动超时/失败路径——超时到底做什么?是否清除凭据、把 unknown 判为登出、破坏已保存的 OAuth token / Web snapshot?

### 结论

**OK**。12 秒启动 deadline 只做一件事:置 `webSessionReadyProvider = true` 释放路由,并触发一次 web session 检查。全部超时/失败路径均**保留**凭据与持久化快照;不存在把"未知超时"判为登出的路径。两个非破坏性行为缺口(登出后重启落公共 Home、live+persisted 双空才判 anonymous 的边角)不属超时路径,分别记入问题 4(D3)与此处解释末尾。

### 证据

**超时做什么**:

- `lib/features/splash/splash_screen.dart:48`
  ```dart
  static const Duration _startupTimeout = Duration(seconds: 12);
  ```
- `lib/features/splash/splash_screen.dart:63-64`
  ```dart
  // Independent of every awaited Future, including a circular restore wait.
  _startupDeadline = Timer(_startupTimeout, () => _finishStartup('deadline'));
  ```
- `lib/features/splash/splash_screen.dart:103-116`:`_finishStartup` 仅置 `_finished`、cancel deadline、
  ```dart
  ref.read(webSessionReadyProvider.notifier).state = true;
  unawaited(_checkSession());
  ```
  无任何凭据/存储操作。`webSessionReadyProvider` 的注释(`lib/core/auth/web_session_status.dart:22`)明确它是"startup readiness only, never web session healthy"。
- 路由侧:`lib/app/router.dart:165-168` ready 前强留在 `/splash`;`lib/app/router.dart:232-241` 超时后 unknown+ready → `/`,注释原文 *"A timed-out restore stays unknown. Keep recovery routes reachable after leaving Splash; redirecting Home back to Splash creates a startup loop."*(即 3d62b45 `ready=true + OAuth unknown` 造成 `/splash→/→/splash` 循环的修复)。

**失败不清凭据(OAuth)**:

- `lib/core/auth/auth_controller.dart:138-140`:`validTokens(forceRefresh: false).timeout(15s)`。
- 瞬时失败保留:`lib/core/auth/auth_controller.dart:152-167`(DAKit 网络类失败 → log "persisted session temporarily unavailable; preserving signed-in state" → `state = signedIn` + `unawaited(_startAccountLoad)`);`lib/core/auth/auth_controller.dart:176-191`(超时/意外异常 catch-all → "session restore failed transiently; preserving state" → `state = signedIn`)。
- 只有 **definitive** 凭据失效才登出:`lib/core/auth/auth_controller.dart:169-175`(`isDefinitiveCredentialFailure` → `saveOAuthSessionKnown(false)`,落到 `:195` `state = signedOut`);策略函数 `:23-58`(`shouldPreserveSessionAfterRestoreFailure`:TimeoutException、非 DAKit 异常一律 preserve;仅 `oauth.session.missing|oauth.refresh.missing|oauth.refresh.invalid|invalid_grant|refresh token invalid/revoked` 判 definitive)。
- `_handleSessionInvalidation`(`lib/core/auth/auth_controller.dart:199-208`)只在 DAKit 上游**主动声明**会话失效时置 signedOut,与超时无关。

**Web snapshot 不被破坏**:

- `lib/core/auth/web_session_store.dart:116` 注释原文 *"The only path that removes the persisted Cookie credentials"*——`clear()` 仅两个调用点:显式登出 `lib/core/auth/web_session_controller.dart:666`(`reason: 'explicit_logout'`)与身份冲突 `lib/core/auth/web_session_controller.dart:338`(`reason: 'identity_mismatch'`)。超时/恢复失败不触碰它。
- cookie restore 失败仅 best-effort:`lib/core/auth/web_session_controller.dart:299-301`(`on Object` 吞掉,注释 "a failed restore only means the user signs in again");控制器内存态保留 `store.read` 的结果(`lib/core/auth/web_session_controller.dart:173-186`)。
- 启动恢复本体只有两步、无清理动作:`lib/features/splash/splash_screen.dart:16-36`(`restore()` = `await auth.initialize()` → `await web.initialize()`)。

**unknown 不会被误判登出**:

- `lib/core/auth/web_session_status.dart:343-359`:非 browser 检查先 `await restorePersistedCookies()`(**join 启动恢复同一 in-flight future**,消除"检查跑在注入之前"的竞态),live cookies 为空时才看持久化数量:
- `lib/core/auth/web_session_status.dart:95-99`
  ```dart
  persistedCookieCount == 0 ? WebSessionStatusState.anonymous : WebSessionStatusState.unavailable
  ```
  配 `lib/core/auth/web_session_status.dart:350-353` 注释 *"That is unavailable, not proof that the user is signed out. A genuinely logged-out account has no persisted cookie snapshot at all."* —— 这正是 v0.5.13 "HTTP verifier 分类为 anonymous" 缺陷的修复。
- `lib/core/auth/web_session_verifier.dart:47-102`(10s 超时,`:68`):非 200、缺 `window.__INITIAL_STATE__` marker、解析失败一律 `unavailable`;只有页面**显式** `anonymous` 才判 anonymous(`:116-137`)。

### 解释

12s deadline 与一切被 await 的 Future 解耦(注释点名"circular restore wait"),超时只切路由。超时后后台恢复继续跑(见问题 2):auth 侧 15s `validTokens` 先后落定 → `signedIn` 状态经 `lib/app/router.dart:183`(`ref.listen(authControllerProvider, (_, _) => authRevision.value++)`)触发路由重估;web 侧 cookie restore 等待 `accountLoad` 后注入、`(isLoggedIn, username)` tuple 变化触发 status 重置与 check。全链无删除动作。

已知边角(不改变 OK 判定):live cookie store 丢失 **且** 持久快照从未成功写入(`report` 在 `empty_capture|missing_userinfo` 时跳过持久化,`lib/core/auth/web_session_controller.dart:366-379`)时,`emptyLiveCookieStatus(0)` 会误判 anonymous——后果是恢复横幅(`needsLogin`)+ 一键进登录 WebView(免密码)恢复,不丢凭据、不丢数据。

---

## 问题 2:Splash 卸载后后台恢复继续——结果是否被 account epoch / generation / recoveryId 守卫?检查与落地之间是否有竞态窗口?

### 结论

**OK(后台事务口径)**。后台恢复由 application-owned 单飞操作继续执行,所有结果落地前必须通过 `generation`/`accountEpoch`/`identityEpoch` + `mounted` 双检;我逐段核对了"检查通过后、写入前"的窗口,**后台路径(restorePersistedCookies、_performCheck、headless probe、RFY)均未发现可交叠的 TOCTOU 窗口**——关键状态写入要么与最后一次检查之间无 `await`,要么经 store 的 `isCurrent` 双检。唯一发现的检查-落地窗口在**可见恢复路径** `report()`/`markHealthy`(与显式登出竞态),按题目口径归问题 4 展开(编号 D1)。

### 证据

**后台恢复确实继续(设计如此)**:

- `lib/features/splash/splash_screen.dart:14-16` 注释 *"leaving Splash does not cancel a late restore"*;`:37` `operation ??= restore()`(重建/重进 Splash join 同一操作);`dispose`(`:72-77`)只 cancel deadline Timer,不取消 restore;`_initialize` 的 `finally`(`:98-99`)保证异常也释放路由。

**代际守卫体系**:

- 身份变化即全部失效:`lib/core/auth/web_session_status.dart:103-126`(监听 `(isLoggedIn, username.trim().toLowerCase())` tuple,变化即:
  ```dart
  _accountEpoch++;
  _generation++;
  _activeCheck = null;
  unawaited(_ref.read(webSessionRefresherProvider).accountChanged());
  _lastSuccess = null;
  ...
  if (mounted) state = const WebSessionStatus();
  ```
  并在 `scheduleMicrotask` 里再查 `epoch == _accountEpoch` 才补发 check)。
- check 捕获三元组:`lib/core/auth/web_session_status.dart:210-244`(`:211` `if (_interactive) return;` 单飞 `:212-213`;`:223` generation、`:224` recoveryId、`:226` epoch;`whenComplete` 以 `identical` 清单飞)。
- 过期证据丢弃:`lib/core/auth/web_session_status.dart:246-247`(`_isCurrent` = mounted && ref.mounted && generation 相等)、`:254-264`
  ```dart
  if (!_isCurrent(evidence.generation)) {
    AppLogger.instance.info('auth', 'verification result discarded: source=... generation=... currentGeneration=... reason=stale');
    return const WebSessionVerdictDecision.keep();
  }
  ```
- `_performCheck` 每个 `await` 之后复查 generation:`lib/core/auth/web_session_status.dart:319`、`:346`、`:357`、`:364`、`:378`、`:402`、`:435`。
- headless probe 双保险:`lib/core/auth/web_session_refresher.dart:86`(20s deadline Timer)+ `:93-97`
  ```dart
  bool _current(...) => identical(_completion, completion) && _ref.mounted &&
      _activeIdentityEpoch == controller.identityEpoch;
  ```
  每个回调前检查(`:108/:111/:123/:133`);`accountChanged()`/`yieldToVisible()` 主动释放。

**cookie restore 无 TOCTOU**:

- `lib/core/auth/web_session_controller.dart:280` epoch/mounted 检查之后到 `:288-292` 的 `state = WebSessionState(...)` 写入之间**无任何 await**(同步落地,事件循环不可交叠);每个 `_setCookie` 前 `:276` 再查;持久化经 `:293-297` `_store.update(..., isCurrent: () => _isCurrentIdentity(epoch))`。
- store 侧双检 + 串行:`lib/core/auth/web_session_store.dart:134`、`:136`(`_performUpdate` 在 read 前、read 后各查一次 `isCurrent`),全部经 `_writeTail` 串行(`:29`、`:122-125`),保证 clear 与 update 的先后序、过期 update 在执行点被丢弃。

**RFY 提交门**:

- `lib/features/home/home_providers.dart:95-103` `ownershipLost()`(epoch != accountEpoch → `account_changed`;!ref.mounted → `provider_disposed`;revision 不符 → `newer_request_won`;token.isCancelled)。
- `lib/features/home/home_providers.dart:279-295` 提交门:现场重读 `cookieHeader`(`:280`)后 `personalizedResultDiscardReason(mounted/sameAccount/sameEpoch/sameRequest/healthy/sameGeneration/sameCredentials/generic)`;策略 `lib/core/feed/personalized_request_policy.dart:4-22` —— **非 generic 结果允许跨 generation/credential 变化采纳**(rfy-4 被丢弃、rfy-5 才接受的修复),generic(`vespa_content_group == 2`,`lib/core/auth/personalized_session_status.dart:80-90`)则丢弃并触发 `recheckAfterWebSignal('rfy-generic-fallback')`。
- 每个物理请求带 transportId,terminal outcome 唯一(`lib/features/home/home_providers.dart:89-92` trace 字段 requestId/provider/recoveryId/accountEpoch/sessionGeneration/credentialRevision/triggerReason/phase)。

**测试佐证**:`test/web_session_mutation_race_test.dart:153`(登出后已发出的原生写入被清)、`:172`(登出后完成的 snapshot read 不能重建持久凭据)、`:184`(旧 browser CSRF 不能更新新身份代际);`test/home_refresh_no_probe_test.dart`("account epoch changes invalidate away-and-back responses"、"a cookie rotation during a feed request discards its result"、"verified same-account recovery adopts a successful in-flight response without second RFY")。

### 解释

后台事务的模式是:捕获代际 → 每次挂起返回后复查 → 落地。我重点核查的落地点——`_restoreWebCookies` 的 state 写入(`lib/core/auth/web_session_controller.dart:288`)、`applyVerification` 的 state 赋值、RFY 的 `putAll`(`lib/features/home/home_providers.dart:337`,门内所有 read 在同一同步段完成)——都不存在"检查通过后、写入前别人改状态"的窗口。跨账号串号另有独立防线:restore 的 `// Never mix cookies from two accounts.`(`lib/core/auth/web_session_controller.dart:263-266`)、report 的 identity_mismatch 清理(`:323-340`)、`shouldRestoreSavedWebSession` 用户名匹配(`:684-693`)、RFY 提交门 `sameAccount/sameEpoch`。发现的一个例外是 `report()`(:318-320 自增 `_identityEpoch` 使其"自我当前化")+ `markHealthy`(`lib/core/auth/web_session_status.dart:489-502` 用自增后的新 generation 恒通过)——这两个落地不检查"登录页外是否发生过显式登出",窗口在问题 4 的 D1 中完整展开。

---

## 问题 3:OAuth pending 事务(PKCE)与 Cookie restore 之间是否存在循环等待或死锁?所有等待是否有界?

### 结论

**OK**:依赖链单向,未发现任何循环等待;所有**会话级**等待均有界。两条底层串行队列(原生 Cookie 队列、secure-storage 写队列)无显式超时,记 P2(D5)——它们的消费者要么有 deadline 兜底(probe),要么造成登录页永久 spinner(可感知、可手动退出)。

### 证据

**依赖图(无环)**:

- cookie restore → account load:`lib/core/auth/web_session_controller.dart:240`
  ```dart
  await _ref.read(authControllerProvider.notifier).accountLoad;
  ```
  (注释:AuthController 故意不阻塞 splash 于 /user/whoami,恢复等账号落定)。
- account load → 仅 OAuth/网络:`lib/core/auth/auth_controller.dart:388-393`(`_accountLoad ??= _loadAccount(...)`,memoized);`:397-424` `_loadAccount` 只调 `OfficialAccountRepository.currentUser()`,**不依赖 web session / cookie / probe** → 无反向边。
- probe → cookie 队列:`lib/core/auth/web_session_refresher.dart:107` `await ...cookieMutations;`(等原生 cookie 写队列排空);队列操作不依赖 probe → 无环。
- 登录页 → bridge:`lib/core/auth/webview_oauth_bridge.dart:48-50` `launch()` 等监听者最多 25×20ms=500ms,超时回退系统浏览器 → 有界。

**有界等待清单**:

| 等待 | 界 | 位置 |
|---|---|---|
| `validTokens` | 15s | `lib/core/auth/auth_controller.dart:138-140`(另 `:243` confirm 路径 15s) |
| `accountLoad`(whoami) | 15s | `lib/core/auth/auth_controller.dart:401-403` |
| HTTP verifier | 10s | `lib/core/auth/web_session_verifier.dart:68` |
| headless probe 总预算 | 20s | `lib/core/auth/web_session_refresher.dart:86`(注释 *"events never extend it"*) |
| 可见 observer 采样预算 | 20s | `lib/core/auth/browser_session_observer.dart:124/:152` |
| 启动 deadline | 12s | `lib/features/splash/splash_screen.dart:48/:63-64` |
| `cancelLogin` 等旧 login op | 2s | `lib/core/auth/auth_controller.dart:337` |
| RFY 单请求 | 60s | `lib/features/home/home_providers.dart:373` |
| bridge 监听者等待 | 500ms | `lib/core/auth/webview_oauth_bridge.dart:48-50` |

3d62b45 启动卡死的直接对策即 `lib/features/splash/splash_screen.dart:63-64` 的独立 deadline(注释点名 circular restore wait)。

**无界 1(原生 Cookie 串行队列)**:`lib/core/auth/web_session_controller.dart:149-171` `_withNativeCookies` 串行化于 `_nativeCookieTail`,单操作无超时(平台通道调用)。消费者:

- 登录页 `_cookiesReady` 门:`lib/features/web_login/web_login_screen.dart:78-82`
  ```dart
  ref.read(webSessionControllerProvider.notifier).cookieMutations.then((_) {
    if (mounted) setState(() => _cookiesReady = true);
  }),
  ```
  无超时;若平台调用挂起,登录页停在 `:455-456` 的 `CircularProgressIndicator`,不会创建 WebView、也不会进入重试路径(P2)。
- probe 同样等它(`web_session_refresher.dart:107`),但有 20s deadline 兜底(`:86`)→ probe 不被拖死。

**无界 2(secure-storage 写队列)**:`lib/core/auth/web_session_store.dart:29/:122-125` `_writeTail` 串行无超时;`logout()` 的 `await webClear`(`lib/core/auth/auth_controller.dart:368`)与 revoke(`:372`)排在其后。存储卡死会推迟 revoke——但 `state = signedOut` 已在 `:355-356` **先行落地**,不影响状态正确性,只影响 Keychain 清理时效(P2)。

### 解释

PKCE 与 cookie restore 之间的耦合点只有一个:cookie restore 等 `accountLoad`(OAuth 侧网络),而 OAuth 侧不回等任何 web session 状态;login flow 中 `authorize()`(auth)与 `_cookiesReady`(web)是并行不互等的。因此"cookie restore 等 account load、account load 等会话、会话等 cookie"的三角不成立。无界的两条队列是平台调用/存储层问题,现有 deadline 结构(12s 启动、20s probe、60s RFY)保证用户永远有 UI 可达(公共 Home / 登录页退出),不会构成死锁,只构成可见的等待缺陷。

---

## 问题 4:explicit logout 后——token、持久 snapshot、pending PKCE 是否全部作废?后台恢复会否复活旧会话?旧残留会否阻塞新登录(12aaeac 模式)?

### 结论

**DEFECT(P1×1 + P2×2)+ RISK/CANNOT-DETERMINE×1**。后台(无头)恢复路径不会复活旧会话(epoch/generation/isCurrent 全链守卫);但**可见恢复路径(登录页 report/markHealthy)没有登出墓碑**,存在把已登出 web 会话复活的现实路径(D1,P1)。logout 不取消 pending PKCE 事务(D2,P2);evidence 墓碑分支把已知登出留成 unknown 导致登出后冷启动落公共 Home(D3,P2)。反向(12aaeac)方面:旧 PKCE、旧 snapshot、旧恢复事务均不会阻塞新登录;但 OAuth 回调在内嵌 WebView 中的唯一捕获点是 `shouldOverrideUrlLoading`,若 DeviantArt authorize 完成跳转是服务端 302,Android WebView 不会回调该钩子——此为 12aaeac 失败模式在 14797b3 中唯一能从代码解释、且未见修复痕迹的候选(R1,CANNOT-DETERMINE,须真机验证)。

### 证据

**A. 正向清理(全部落位)**:

- `lib/core/auth/auth_controller.dart:355-356`(状态先落地,注释 *"Fence Web/RFY work immediately, before best-effort network revocation or secure-storage cleanup"*)
  ```dart
  _authEpoch += 1;
  state = const AuthState(status: AuthStatus.signedOut);
  ```
- `:358-366` `webSessionController.clear().catchError(...)` → `:367` `await AppPreferences.saveOAuthSessionKnown(false)`(**证据墓碑**)→ `:368` `await webClear` → `:369-382` `logout(revoke: true)`,失败再 `session.logout(revoke: false)`。
- `lib/core/auth/web_session_controller.dart:652-667` `clear()`:
  ```dart
  _identityEpoch++;
  _cookieRestore = null;
  state = const WebSessionState(isLoggedIn: false);
  ```
  → `_withNativeCookies(deleteAllCookies)`(失败仅 log "explicit logout native clear failed")→ `_store.clear(reason: 'explicit_logout')`(持久快照删除,`lib/core/auth/web_session_store.dart:116` 注释确认这是唯一删除路径,`:163` log "cleared persisted snapshot reason=")。

**B. 后台恢复不会复活(无头口径)**:

- 协调器闸门关死:`lib/core/auth/web_session_coordinator.dart:26-33`
  ```dart
  shouldVerify: () => ref.mounted &&
      ref.read(webSessionControllerProvider).isLoggedIn == true &&
      !ref.read(webSessionStatusProvider).needsLogin,
  ```
  clear 后 `isLoggedIn=false`,周期与信号触发的 check 全部跳过。
- 若 check/probe 正在飞:clear → tuple 变化 → `web_session_status.dart:109-115` generation++ → `applyVerification` 以 stale 丢弃(`:254-264`);probe 结果被 `_activeIdentityEpoch != controller.identityEpoch` 拦(`web_session_refresher.dart:93-97`);restore 的 epoch 检查(`web_session_controller.dart:245/258/261/276/280`)+ store `isCurrent` 双检(`web_session_store.dart:134/:136`)拦住晚到的写入。测试:`test/web_session_mutation_race_test.dart:153/:172/:184`。
- 冷启动不复活(墓碑):`lib/core/auth/auth_controller.dart:114-132` evidence==signedOut → 不恢复 token,且 `:120-121` `session.logout(revoke: false)` 清残留;`shouldRestoreOAuthSessionAfterEvidence`(`:32-33`)以 recorded logout 为权威。

**C. 反向:旧状态不阻塞新登录(修复到位)**:

- 旧 PKCE:`lib/core/auth/auth_controller.dart:227-231`
  ```dart
  Future<void> retryLogin() async {
    if (state.status == AuthStatus.signedIn) return;
    await cancelLogin();
    await login();
  }
  ```
  `cancelLogin()`(`:318-348`)→ `:325` `authorization.cancelPending()` + `:337` 旧操作 2s 超时;登录页打开即走 retryLogin(`lib/features/web_login/web_login_screen.dart:95-98`,注释 *"A stale transaction from an earlier login visit must not block the new one"*)。测试:`test/oauth_retry_lifecycle_test.dart:7-8` "cancelled authorization can immediately create a fresh transaction"。
- 旧 headless probe:`web_login_screen.dart:76` `yieldToVisible()` 释放;旧后台 check:`:93` `beginInteractiveRecovery()` → `web_session_status.dart:211` `if (_interactive) return;` 挂起。
- 旧 snapshot:restore 侧 `web_session_controller.dart:263-266`(`// Never mix cookies from two accounts.`)+ `shouldRestoreSavedWebSession`(`:684-693`,signedOut 直接 false);report 侧 `:323-340` mismatch → `deleteAllCookies` + `store.clear('identity_mismatch')`。
- 登录页对老账号渲染的页面也受 `_reportSeq` 序号保护(`web_login_screen.dart:193/:202/:219/:250-254`)。

**D. 缺陷 D1(P1)可见恢复无登出墓碑——可复活已登出的 web 会话**:

- `lib/core/auth/web_session_controller.dart:318-320`(report 入口):
  ```dart
  if (loggedIn && username.toLowerCase() != state.username.toLowerCase()) {
    _identityEpoch++;
  }
  ```
  当 `state` 是被 `clear()` 清空的结果(`isLoggedIn:false, username:''`)时,这一自增把本应作废的旧报告"自我当前化"——后续 `:381-392` 的 `state` 写入与 `store.update(cookies: ..., isCurrent: () => _isCurrentIdentity(epoch))` 全部通过(epoch 已被自己接管)。`report()` 与其调用方全程不检查 `authControllerProvider` 的登出意图;`web_login_screen.dart:250-254` 的复查读的是**已被复活**的 state,拦不住。
- `markHealthy` 恒接受:`lib/core/auth/web_session_status.dart:489-502` 先 `_generation++` 再以新 generation 调 `applyVerification` → 永远不是 stale。
- 触发序列(不需要微秒级竞态):登录页(用于恢复的可见 WebView,`!_serverConfirmedWebSession`,observer 存活)→ 从登录页自身 AppBar push `/settings`(`web_login_screen.dart:406-410`)→ 显式登出 → 返回登录页;WebView 仍渲染着已登出账号的已登录页面,任何主帧导航触发 `onLoadStop`/`onUpdateVisitedHistory` 的 `restart()`(`:587-592`/`:598-603`,条件 `!_serverConfirmedWebSession`)→ 新 observer 首采样(无去重基线)→ `_reportWebSession` → `report()` 复活 `isLoggedIn=true + username`。若 `readData()`(`web_login_screen.dart:218`)恰在 clear 的 `deleteAllCookies` 落地前完成,旧账号 `capturedCookies` 还会经 `:243-249` → `web_session_controller.dart:386-392` **重写持久 snapshot**(此后 status 走 unavailable 而非 anonymous,恢复横幅消失)。
- 自限性(故 P1 而非 P0):OAuth 已 signedOut,`shouldRestoreSavedWebSession` 拒绝注入(`web_session_controller.dart:689`);RFY 因 cookieHeader 空走 `home_providers.dart:374-387` → `:137-147` 不可用路径——**不会出现旧账号个性化内容泄露**;再次登出可清理;跨账号串号被 identity gate 拦。破坏的是"只有显式登出清除会话"的 SPEC 不变量。
- 最小修复(不重构):`clear()` 增加单调 `logoutRevision`;`report()`/`markHealthy`/`ensurePersistentSnapshot` 捕获该值,在**状态写入与 `store.update` 落地前**比对,不等则丢弃。注意不能用 `auth.status == signedOut` 判定(首次登录时 auth 同样是 signedOut)。

**E. 缺陷 D2(P2)logout 不取消 pending PKCE**:

- `lib/core/auth/auth_controller.dart:350-383` 全文无 `cancelPending`(对照 `cancelLogin():325` 有)。登录进行中登出:PKCE 事务残留于 `SecurePendingAuthorizationStore`(`lib/core/runtime/app_runtime.dart:155-157`);若回调恰在登出后完成,DAKit 先落新 token,epoch 守卫(`:292`)保住状态,证据墓碑保住下次冷启动(`:114-132`,含 `:120-121` 清残留),但本会话内该 token 无人使用地留在 Keychain 直至冷启动。
- 最小修复:`logout()` 在 revoke 前调用 `runtime.oauth!.authorization.cancelPending()`(try/catch 吞错,与 `cancelLogin` 同款)。

**F. 缺陷 D3(P2)evidence==signedOut 分支把 AuthStatus 留在 unknown**:

- `lib/core/auth/auth_controller.dart:130-131` 该分支 `return` 前未设置状态(state 停留 unknown)。后果:显式登出 + 冷启动 → `authRedirect(unknown, '/splash', ready:true)` → `'/'`(`lib/app/router.dart:238`),用户落公共 Home 而非 `/web-login`;对照首次安装(definitive 路径 `:195` signedOut → `lib/app/router.dart:249-251` → `/web-login`)。可导航、无数据危害,行为不一致。
- 最小修复:该分支显式 `state = const AuthState(status: AuthStatus.signedOut);`。

**G. R1(RISK / CANNOT-DETERMINE)OAuth 回调唯一捕获点(12aaeac 失败模式的代码层候选)**:

- 内嵌 WebView 中 `dakit://oauth/callback` 仅由 `shouldOverrideUrlLoading` 捕获:`lib/features/web_login/web_login_screen.dart:534-557`
  ```dart
  if (uri.scheme == 'dakit' && uri.host == 'oauth') {
    _bridge?.addCallback(uri);
    ...
    return NavigationActionPolicy.CANCEL;
  }
  ```
  → `lib/core/auth/webview_oauth_bridge.dart:33-40` `addCallback`(过滤 scheme/host,log "callback received path=...")→ DAKit 完成 PKCE。
- **没有兜底**:无 `onLoadError`/`onReceivedError` 处理器;`AppLinksCallbackUriSource`(`lib/core/runtime/app_runtime.dart:159-162` 的 `MergedCallbackUriSource(initial: AppLinks..., others: [bridge.callbacks])`)只接收 OS 级 intent——WebView 内部导航到自定义 scheme 不会派发 intent,Android WebView 自己以 `net::ERR_UNKNOWN_URL_SCHEME` 失败。
- Android WebView 对**服务端 30x 跳转不回调** `shouldOverrideUrlLoading(AOSP 文档行为)。若 DeviantArt authorize 完成到 redirect_uri 的跳转是 302(隐式授权/auto-approve 的常见形态),回调在内嵌 WebView 中必然丢失。
- 回调丢失的下游(与 12aaeac 真机特征逐项吻合):`authorize()`(`lib/core/auth/auth_controller.dart:291`,`await runtime.oauth!.authorize();` **无超时**)挂起 → `isLoggingIn=true` → 账号不刷新(`_loadAccount` 永不执行 `:296`)→ 不自动返回首页(`web_login_screen.dart:545-554` 的 loadUrl(home) 不会发生,`:372-389` 关闭门不满足)→ 登录页 `_refresh` 的重试门 `:179-181`
  ```dart
  } else if (!auth.oauthSignedIn && auth.error != null && !auth.isLoggingIn) {
    unawaited(_authController.retryLogin());
  ```
  三条件(`error != null`、`!isLoggingIn`)均不满足 → **页内无恢复手段**,只能关闭重开(下次 `retryLogin` → `cancelLogin` → `cancelPending`)。RFY 报 Web Session 不可用与"OAuth 未完成"一致(`needsLogin`/unverified 状态下 `home_providers.dart:171-189` 抛 `rfy.session.unverified`)。
- 但 **DeviantArt 实际用 302 还是 JS location 跳转无法从代码判定**(v0.5.13 的内嵌登录曾在真机成功过,提示跳转方式可能触发钩子),故对 12aaeac 失败是否复现于 14797b3 记 **CANNOT-DETERMINE**,列为真机观察点第一优先。配套缓解缺陷 D4(P2):`authorize()` 无超时——最小修复 `authorize().timeout(60s)` 走 `:297-313` 的 error 路径(signedOut+error),打开 `_refresh` 重试门,即使 R1 成立用户也有页内恢复手段。

### 解释

登出的三层清理(state 先行、web clear、证据墓碑)对**后台**路径是完备的:无头 probe、status check、cookie restore、RFY 都被代际/纪元/`isCurrent` 拦截,且有 mutation-race 测试背书。不完备的是**可见恢复面**:登录页作为"已登录用户恢复 web session"的指定入口,其 report/markHealthy 与显式登出之间存在不受代际保护的落地(D1)。反向(12aaeac)排查中,旧 PKCE/旧 snapshot/旧恢复事务的阻塞均已消除且各有测试;唯一存疑的结构性短板是回调捕获单点(R1)+ 无超时 authorize(D4)——这对真机复测具有最高优先级。

---

## 问题 5:登录成功后——账号加载、Web Session 判 healthy、首页刷新是否完整衔接?有没有漏一环导致首页仍显示匿名/通用内容?

### 结论

**OK**。代码层五个环节(页证据→report/markHealthy;回调→authorize 返回→账号加载;关闭门;首页 identity 重建;healthy 转变→recoverInitialPage)逐环闭合,并有 widget/policy 测试覆盖。唯一不可由代码判定的环节仍是 R1 的回调捕获(若回调不来,链条从第 2 环起不发生,首页将停留通用内容 + 恢复横幅——这正是 12aaeac 的表现)。

### 证据

**环 1:WebView 页证据 → report + markHealthy**

- observer 证据回调:`lib/features/web_login/web_login_screen.dart:499-515`(onEvidence → `_reportWebSession(serverConfirmedNavigation: page.hasIdentity, evidence: page)`)。
- `_reportWebSession`(`:187-268`):`:218` `readData()` 一次原子读(cookies+username);`:220` 'anonymous'→'';`:226-234` Cookie 在 /users/login 时一次性导航 home 收集页面身份(Cookie 单独不作确认,注释 `:222-223`);`:243-249`
  ```dart
  await ref.read(webSessionControllerProvider.notifier).report(
    csrf: csrf, username: username, capturedCookies: sessionData?.cookies);
  ```
- report 落地:`lib/core/auth/web_session_controller.dart:381-392`(state + `_store.update(cookies: loggedIn ? capturedCookies : null, ...)` 持久化有效快照);`:270`(web_login_screen)`_sessionStatus.markHealthy(serverUsername: username)` → `lib/core/auth/web_session_status.dart:489-502` healthy;`:278-280` `artworkSessionRecoveryProvider` 失效化 artwork 详情链(`lib/features/artwork/artwork_detail_providers.dart:37-48`)。
- 注释 `web_login_screen.dart:273-277`:登录页**永不** invalidate `personalizedFeedProvider`——首页恢复只走 healthy 转变监听,避免二次拉取清列表。

**环 2:OAuth 回调 → authorize 返回 → 账号加载**

- 回调捕获(R1 唯一点):`web_login_screen.dart:534-557` → `webview_oauth_bridge.dart:33-40`;捕获后导航 home(`:545-554`,注释 *"its onLoadStop then reports the real web session"*),完成环 1→环 3 闭环。
- `lib/core/auth/auth_controller.dart:291-296`:`authorize()` → epoch 复查 → `saveOAuthSessionKnown(true)` → `_loadAccount(epoch)` → `state = AuthState(status: signedIn, account: account)`(`:406`)。

**环 3:关闭门**

- `lib/features/web_login/web_login_screen.dart:372-389`(`ref.listen<AuthState>`:signedIn+account → `_closeAfterReport = _failedNavigation == null`;若 `_serverConfirmedWebSession` 已真 → 立即关 `'oauth_completed_after_web'`)。
- web report 侧:`:283-295` + 策略 `:631-637`
  ```dart
  serverConfirmedNavigation && (oauthSignedIn || closeAfterOAuthReport)
  ```
  → `'login_completed'`;只确认 web 未完成 OAuth 时**不关**(等待,`:296-302` log "waiting for OAuth"),防"关闭早于 web session 记录"(`:368-371` 注释)。
- 测试:`test/web_login_close_policy_test.dart:6/:17/:28/:39` 四种组合;`test/web_login_lifecycle_test.dart:279` "explicit logout then PKCE login restores account, closes and owns one RFY"(参数化 none/authorize failure/home failure)。

**环 4+5:首页 identity 重建与恢复**

- `lib/features/home/home_providers.dart:55-57` `ref.watch(webSessionControllerProvider.select(personalizedFeedSessionIdentity))`((isLoggedIn, username) 变化 → provider 重建、新 controller);`:389` 创建即 `unawaited(controller.refresh())`;`:392-403` 缓存 hydration。
- `:404-410` healthy 转变监听:
  ```dart
  ref.listen(webSessionStatusProvider, (previous, next) {
    if (previous?.isHealthy == false && next.isHealthy) {
      unawaited(controller.recoverInitialPage());
    }
  });
  ```
- `lib/core/feed/artwork_feed_controller.dart:208-217` `recoverInitialPage()`:(有 items 且残留 error)或(无 items 且 error)时以 `'session_recovered'` 续拉首屏;`_performFirstPageFetch` 的 revision 复查(`:245`)防过期提交。
- OAuth 未完成不阻塞个性化内容:RFY 门槛只查 web session(`home_providers.dart:137-147`),不查 OAuth——web 先恢复时首页先个性化,账号头像等 OAuth 数据后到。
- 失败分支:导航失败有 banner+手动重试(`web_login_screen.dart:445-446/:166-182`);WAF 锁定 `markLocked`(`:331-335`)。

### 解释

链路上每个"等待对方"的环节都有明确的完成信号和监听者:web→关闭门(close policy),OAuth→关闭门(auth listener),healthy→首页(recover 监听),identity→provider(select 重建)。测试分别锁定了 close policy、logout→login 全链、anonymous verdict 显示恢复 UI 而非通用内容(`test/home_refresh_no_probe_test.dart:710` "an anonymous web-session verdict shows recovery, not generic content")、verification recovery 自动续拉停止的首屏(`:349` "verification recovery automatically resumes a stopped initial feed")。未发现漏环;R1 是链条上唯一可能断掉且代码无法自证的点。

---

## 问题 6:测试覆盖

### 结论

**覆盖密度高(83 个测试文件中约 40 个直接覆盖本域),核心守卫与修复点均有针对性测试;存在 5 个真实缺口**,其中 3 个直接对应本次审计发现的缺陷。

### 覆盖清单(关键测试)

- **启动门/路由**:`test/startup_gate_test.dart:26-27` "startup $mode releases routing without changing unknown identity"(参数化 pending/cycle/exception/success);`test/auth_routing_test.dart:6/:10/:18/:22/:43/:53/:66`(含 "unknown auth after deadline never redirects recovery routes to splash"、"explicit logout returns account routes to public Home");`test/shell_redirect_regression_test.dart:9-11`。
- **恢复失败保留策略**:`test/auth_restore_policy_test.dart:8/:18/:34/:67/:93`("cold-start timeout does not force a persisted user to sign in again"、"network, upstream and Keychain failures preserve the session"、"only missing or revoked credentials require authorization"、"legacy DeviantArt invalid_request refresh response is definitive"、"a transient restore failure always preserves the session")。
- **登出证据与重登录**:`test/auth_session_evidence_test.dart:14/:21/:33`;`test/oauth_retry_lifecycle_test.dart:7-8`;`test/web_login_lifecycle_test.dart:279/:566`(logout→PKCE 登录全链、challenge 不重载 WebView)。
- **竞态/代际**:`test/web_session_mutation_race_test.dart:153/:172/:184`;`test/web_session_status_test.dart:205-207`(overlapping recovery completions 保留各自 recoveryId)、`:255`(only healthy is usable)、`:284`(cooldown)、`:294-460`(server verification 矩阵:healthy 仅服务器确认、real-browser anonymous 权威、real-browser 失败 unverified 不登出、challenged HTTP 经真浏览器恢复、empty live+saved→unavailable、concurrent checks 单飞)。
- **RFY 所有权/提交门**:`test/home_refresh_no_probe_test.dart:189-710`(generic 拒绝、账号切换不发过期传输、cookie 轮换丢弃、同账号在飞响应采纳、away-and-back epoch 失效、pull-to-refresh 不触发首页 probe、缓存缺失不阻塞首屏、anonymous verdict 显示恢复 UI);`test/home_pagination_no_auth_damage_test.dart:167/:220`;`test/personalized_request_policy_test.dart`;`test/personalized_feed_refresh_policy_test.dart`;`test/personalized_session_status_test.dart`。
- **probe/observer**:`test/web_session_refresher_lifecycle_test.dart:106/:128/:162/:183/:203/:233/:249`(CSRF-only 不提前终止、多次 challenge、visible handoff 拒绝晚到身份、account change 重建 host、startup timeout 先于卡死 teardown 返回、provider disposal 释放等待者);`test/web_session_refresher_probe_test.dart`(5);`test/browser_session_observer_test.dart:8/:26/:41/:64/:89/:106/:126/:149/:177/:196/:221`。
- **verdict/cookie/store/coordinator**:`test/web_session_verdict_policy_test.dart:19-186`(13 条矩阵);`test/web_session_cookies_test.dart:34/:208/:251/:293/:329/:396`(restore 修复缺失 cookie、identity gate、anonymous probe 保留、import 回滚);`test/web_session_store_test.dart:90/:213`;`test/web_session_coordinator_test.dart:145/:255/:389`(含 "a signed-out session never starts the verdict chain");`test/session_decoupling_test.dart:101/:192/:289`;`test/media_session_signal_test.dart`(8)。

### 真实缺口

1. **D1 对应**:无任何测试覆盖"可见登录页 report/markHealthy 与显式登出并发"——`web_session_mutation_race_test.dart` 只覆盖原生写入、snapshot read 与 CSRF epoch 三个后台侧窗口,未覆盖 report() 复活路径(登录页推 settings 登出后返回的序列)。
2. **D2 对应**:无测试断言 logout 后 `SecurePendingAuthorizationStore` 为空 / `cancelPending` 被调用;也无 "in-flight 回调在登出后完成" 的落库残留断言。
3. **D3 对应**:`auth_session_evidence_test.dart:13-31` 只测 `shouldRestoreOAuthSessionAfterEvidence` 纯函数;`initialize()` 的 evidence==signedOut 分支(状态停留 unknown 及路由后果)无行为测试。
4. **R1/D4 对应**:widget 测试直接向 bridge 注入回调模拟授权完成(`web_login_lifecycle_test` 系列),**真实 `shouldOverrideUrlLoading` 的触发条件(302 vs JS 跳转)在测试环境中不可复现**——这正是 12aaeac 测试全绿但真机 FAIL 的结构原因;`authorize()` 无超时的挂起路径也无测试。
5. **D5 对应**:原生 Cookie 队列 / secure-storage 挂起(登录页 `_cookiesReady` 永久 spinner)无测试。

---

## 总体结论

`14797b3` 对原始故障的两类缺陷修复在代码与测试层面成立:HTTP 验证器不再把"未知"判为登出(`emptyLiveCookieStatus`、verifier 策略),RFY 采纳规则允许同账号非 generic 在飞响应跨代际采纳(`personalizedResultDiscardReason`),提交门与 ownershipLost 消灭了 rfy-4 丢弃类问题;启动 12s deadline 独立于一切 await,3d62b45 的路由循环在 `authRedirect` 与 `startup_gate_test` 中有明确对策;后台恢复的代际守卫体系(identityEpoch/accountEpoch/generation/recoveryId + isCurrent 双检 + _writeTail 串行)完整且被 mutation-race 测试覆盖。登出清理在**后台口径**下成立:token revoke、web clear(内存+原生+持久)、证据墓碑,后台恢复不复活旧会话。

审计发现的问题集中在两处:**可见恢复面缺登出墓碑**(D1,P1——report/markHealthy 可复活已登出 web 会话,违反 SPEC 登出不变量,但受 identity gate 与空 cookieHeader 自限,不会泄露旧账号内容);**OAuth 回调捕获单点**(R1——`shouldOverrideUrlLoading` 是内嵌 WebView 中 `dakit://oauth/callback` 的唯一捕获点,无 onLoadError 兜底,若 DA authorize 完成跳转为服务端 302 则回调必然丢失,且 `authorize()` 无超时导致登录页无页内恢复手段,与 12aaeac 真机失败特征逐项吻合,但跳转机制代码层不可判定)。其余为 P2:logout 不取消 pending PKCE(D2)、登出墓碑分支状态留 unknown 导致重启落公共 Home(D3)、authorize 无超时(D4)、原生/存储队列无界等待(D5)。

## 缺陷列表(按严重级别;均为最小修复建议,不做重构)

| 编号 | 级别 | 位置 | 缺陷 | 最小修复 |
|---|---|---|---|---|
| D1 | **P1** | `lib/core/auth/web_session_controller.dart:318-320/:381-392`、`lib/core/auth/web_session_status.dart:489-502` | 可见恢复(登录页 report/markHealthy)无登出墓碑;登录页推 settings 登出后返回,仍渲染旧账号已登录页面的 WebView 经 restart() 重采样,report() 借 `_identityEpoch++` 自我当前化并复活 `isLoggedIn=true`;若 readData 早于 deleteAllCookies,旧账号 snapshot 被重写持久化(恢复横幅消失)。 | `clear()` 增加单调 `logoutRevision`;`report()`/`markHealthy`/`ensurePersistentSnapshot` 捕获并在状态写入与 `store.update` 落地前比对,不等则丢弃。(勿用 `auth.status==signedOut` 判定,首次登录同态。) |
| D2 | P2 | `lib/core/auth/auth_controller.dart:350-383` | logout 未取消 pending PKCE 事务;in-flight 回调在登出后完成会把新 token 落库(epoch 守卫保状态、墓碑保冷启动,但 token 残留 Keychain 至下次冷启动)。 | `logout()` 在 revoke 前调用 `runtime.oauth!.authorization.cancelPending()`(try/catch 吞错,与 cancelLogin:325 同款)。 |
| D3 | P2 | `lib/core/auth/auth_controller.dart:130-131` | evidence==signedOut 分支 return 前未设状态,AuthStatus 停留 unknown;显式登出+冷启动落公共 Home 而非 /web-login(与首次安装行为不一致)。 | 该分支显式 `state = const AuthState(status: AuthStatus.signedOut);`。 |
| D4 | P2 | `lib/core/auth/auth_controller.dart:291` | `await runtime.oauth!.authorize()` 无超时;回调丢失即永久挂起(isLoggingIn=true),登录页 `_refresh` 重试门(`web_login_screen.dart:179-181`)要求 `error!=null && !isLoggingIn`,双不满足,页内无恢复。 | `authorize().timeout(60s)` → 走 `:297-313` error 路径(signedOut+error),打开重试门。 |
| D5 | P2 | `lib/core/auth/web_session_controller.dart:149-171`、`lib/core/auth/web_session_store.dart:29/:122-125`、`lib/features/web_login/web_login_screen.dart:78-82` | 原生 Cookie 队列与 secure-storage 写队列无界;登录页 `_cookiesReady` 门无超时,平台通道挂起时登录页永久 spinner。 | `cookieMutations` 消费处加超时(如 10s)降级放行(`_cookiesReady=true` 或显示重试),probe 已有 20s deadline 可不动。 |
| R1 | RISK / CANNOT-DETERMINE | `lib/features/web_login/web_login_screen.dart:534-557`、`lib/core/runtime/app_runtime.dart:159-162` | 内嵌 WebView 中 OAuth 回调唯一捕获点为 `shouldOverrideUrlLoading`(无 onLoadError 兜底;AppLinks 源不触发于内部导航);Android WebView 对服务端 30x 不回调该钩子。若 DA authorize 完成是 302,回调丢失 → D4 挂起 → 12aaeac 失败模式。跳转机制(302 vs JS location)代码层不可判定。 | 真机验证观察点 1-2;若确认为 302,最小加固:补 `onReceivedError` 中对 `ERR_UNKNOWN_URL_SCHEME`/`dakit://` URL 的解析回喂 `bridge.addCallback`,或 authorize 路径改用 `initialUrlRequest` 之外的 scheme handler。 |

## 真机观察点(验收测试建议)

1. **R1 直接检验(最高优先)**:主动退出后重新登录(12aaeac 复现路径),logcat 过滤 `oauthBridge`:应出现 `callback received path=/callback listener=...`(`webview_oauth_bridge.dart:37`)。未出现即 R1 成立——记录 authorize 完成页的跳转形态(WebView 是否报 `ERR_UNKNOWN_URL_SCHEME`,`onLoadStart` 的 `nav seq=... event=load_start` 日志 `web_login_screen.dart:563-567`)。
2. **D4 检验**:若观察点 1 未出现回调,观察 `auth` 日志是否停在 `login: starting OAuth authorize`(`auth_controller.dart:290`)无后续;点登录页刷新按钮确认无反应(重试门三条件)。
3. **启动超时后续恢复**:断网/慢网冷启动,确认 `ready=true reason=deadline`(`splash_screen.dart:109`)后,网络恢复时出现 `restore event=account_settled`(`web_session_controller.dart:243`)与 `restore verified username=...`(`:284`),首页最终转个性化(RFY trace `phase=accepted`)。
4. **D1 检验**:已登录账号打开登录页(恢复入口)→ 不等确认,推 settings → 登出 → 返回登录页并触发任意导航;观察登出时间戳之后是否再出现 `web session report ... isLoggedIn=true username=<旧账号>`(`web_login_screen.dart:240-241`)与 `web-session` 持久化日志。
5. **RFY 所有权连续性**:对照原始故障,验证 rfy trace 中 `requestId/accountEpoch/sessionGeneration/credentialRevision` 与 `terminalOutcome`(accepted|discarded|failed)一一对应,成功响应(24 项)不再被同代际丢弃。
6. **登出后冷启动路由**:显式登出 → 重启应用,记录落地页(预期公共 Home,即 D3;修复后应 `/web-login`)。
